import Foundation
import IOKit
import IOKit.ps

// MARK: - Metrics

struct NetworkRates: Equatable {
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
}

struct DiskRates: Equatable {
    let readBytesPerSecond: Double
    let writeBytesPerSecond: Double
}

struct DiskSpace: Equatable {
    let totalBytes: Double
    let freeBytes: Double
    var usedFraction: Double? { totalBytes > 0 ? min(1, max(0, 1 - freeBytes / totalBytes)) : nil }
}

struct BatteryStatus: Equatable {
    enum State: Equatable { case charging, onAC, discharging }
    var fraction: Double?
    var state: State
    var minutesRemaining: Int? = nil
    /// What the whole Mac draws right now, from any source.
    var usageWatts: Double? = nil
    /// What flows into the battery: 0 unless it is charging, nil when unreadable.
    var chargeWatts: Double? = nil

    /// Telemetry is preferred; voltage times current is the fallback on Macs
    /// without it. Battery power is signed: negative means it is supplying.
    static func power(state: State, systemLoadMilliwatts: Int64?, batteryMilliwatts: Int64?,
                      millivolts: Int64?, milliamps: Int64?) -> (usage: Double?, charge: Double?) {
        let terminal = millivolts.flatMap { mv in milliamps.map { Double(mv) * Double($0) / 1_000_000 } }
        var usage: Double?
        if let systemLoadMilliwatts, systemLoadMilliwatts > 0 {
            usage = Double(systemLoadMilliwatts) / 1000
        } else if state == .discharging, let terminal {
            usage = abs(terminal)
        }
        guard state == .charging else { return (usage, 0) }
        return (usage, batteryMilliwatts.map { max(0, Double($0) / 1000) } ?? terminal.map { max(0, $0) })
    }
}

/// One reading of everything tinyStats measures; nil means not available.
struct Sample: Equatable {
    var cpu: Double? = nil
    var gpu: Double? = nil
    var ram: Double? = nil
    var net: NetworkRates? = nil
    var battery: BatteryStatus? = nil
    var disk: DiskSpace? = nil
    var diskIO: DiskRates? = nil
    var swapUsedBytes: Double? = nil
}

/// Per-second rates from pairs of cumulative counters, one pair per key. A key
/// appearing or disappearing, or a counter that fell (reset), starts a new
/// baseline, so none of them ever reads as a spike.
struct CounterRates<Key: Hashable> {
    typealias Counters = [Key: (UInt64, UInt64)]
    private var baseline: (counters: Counters, time: TimeInterval)?

    /// Nil for the first reading of a baseline and when nothing is counted.
    mutating func update(_ counters: Counters, at time: TimeInterval) -> (Double, Double)? {
        defer { self.baseline = counters.isEmpty ? nil : (counters, time) }
        guard let previous = baseline, time > previous.time, counters.count == previous.counters.count else { return nil }
        var sum = (0.0, 0.0)
        for (key, now) in counters {
            guard let then = previous.counters[key], now.0 >= then.0, now.1 >= then.1 else { return nil }
            sum.0 += Double(now.0 - then.0)
            sum.1 += Double(now.1 - then.1)
        }
        let interval = time - previous.time
        return (sum.0 / interval, sum.1 / interval)
    }
}

final class Metrics {
    static let hasBattery = readBattery() != nil
    private static let diskSpaceInterval: TimeInterval = 30
    /// Taken once: every `mach_host_self()` adds a send right that is never given back.
    private static let host = mach_host_self()

    private var cpuTicks: [UInt32]?
    private var networkRates = CounterRates<String>()
    private var diskRates = CounterRates<UInt64>()
    private var diskSpaceCache: (time: TimeInterval, value: DiskSpace?)?

    /// Rates and CPU load over a pause in sampling would average the whole gap.
    func restartBaselines() {
        cpuTicks = nil
        networkRates = CounterRates()
        diskRates = CounterRates()
    }

    func cpu() -> Double? {
        guard let info = Self.hostStatistics(host_cpu_load_info(), { host_statistics($0, HOST_CPU_LOAD_INFO, $1, &$2) })
        else { return nil }
        let ticks = [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
        defer { cpuTicks = ticks }
        guard let previous = cpuTicks else { return nil }
        let delta = zip(ticks, previous).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        return total > 0 ? (total - delta[Int(CPU_STATE_IDLE)]) / total : nil
    }

    func gpu() -> Double? {
        Self.busiest(Self.services("IOAccelerator") {
            ((Self.property($0, "PerformanceStatistics") as? [String: Any])?["Device Utilization %"] as? NSNumber)?.doubleValue
        })
    }

    /// The busiest GPU, as a fraction: summed over several GPUs the figure
    /// would mean nothing. Readings outside 0...100 % are dropped.
    static func busiest(_ percents: [Double]) -> Double? {
        percents.filter { (0...100).contains($0) }.max().map { $0 / 100 }
    }

    func ram() -> Double? {
        Self.hostStatistics(vm_statistics64(), { host_statistics64($0, HOST_VM_INFO64, $1, &$2) }).flatMap {
            Self.memoryUsed($0, pageSize: UInt64(vm_kernel_page_size), total: ProcessInfo.processInfo.physicalMemory)
        }
    }

    /// Activity Monitor's "Memory Used": app memory (anonymous pages that are
    /// not purgeable), wired and compressed. File-backed cache does not count.
    static func memoryUsed(_ vm: vm_statistics64, pageSize: UInt64, total: UInt64) -> Double? {
        let app = UInt64(vm.internal_page_count) - min(UInt64(vm.purgeable_count), UInt64(vm.internal_page_count))
        let pages = app + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
        return total > 0 ? min(1, Double(pages * pageSize) / Double(total)) : nil
    }

    func network() -> NetworkRates? {
        networkRates.update(Self.interfaceCounters(), at: ProcessInfo.processInfo.systemUptime).map {
            NetworkRates(downloadBytesPerSecond: $0.0, uploadBytesPerSecond: $0.1)
        }
    }

    /// Bytes per second across all block devices.
    func diskActivity() -> DiskRates? {
        let counters = Self.services("IOBlockStorageDriver") { service -> (UInt64, (UInt64, UInt64))? in
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS,
                  let stats = Self.property(service, "Statistics") as? [String: Any],
                  let read = stats["Bytes (Read)"] as? NSNumber, let write = stats["Bytes (Write)"] as? NSNumber else { return nil }
            return (id, (read.uint64Value, write.uint64Value))
        }
        return diskRates.update(Dictionary(counters) { first, _ in first }, at: ProcessInfo.processInfo.systemUptime).map {
            DiskRates(readBytesPerSecond: $0.0, writeBytesPerSecond: $0.1)
        }
    }

    /// Free space counts purgeable data, like Finder. Refreshed rarely: the
    /// value moves slowly and the query is the most expensive one here.
    func diskSpace() -> DiskSpace? {
        let now = ProcessInfo.processInfo.systemUptime
        if let cache = diskSpaceCache, now - cache.time < Self.diskSpaceInterval { return cache.value }
        var value: DiskSpace?
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                         .volumeAvailableCapacityKey]
        if let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys), let total = values.volumeTotalCapacity {
            let important = values.volumeAvailableCapacityForImportantUsage.flatMap { $0 > 0 ? Double($0) : nil }
            if let free = important ?? values.volumeAvailableCapacity.map(Double.init) {
                value = DiskSpace(totalBytes: Double(total), freeBytes: free)
            }
        }
        diskSpaceCache = (now, value)
        return value
    }

    func swapUsed() -> Double? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        return sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 ? Double(usage.xsu_used) : nil
    }

    func sample() -> Sample {
        Sample(cpu: cpu(), gpu: gpu(), ram: ram(), net: network(), battery: Self.readBattery(), disk: diskSpace(),
               diskIO: diskActivity(), swapUsedBytes: swapUsed())
    }

    // MARK: Sources

    private static func hostStatistics<Info>(_ empty: Info,
                                             _ read: (host_t, UnsafeMutablePointer<integer_t>, inout mach_msg_type_number_t) -> kern_return_t) -> Info? {
        var info = empty
        var count = mach_msg_type_number_t(MemoryLayout<Info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { read(host, $0, &count) }
        }
        return result == KERN_SUCCESS ? info : nil
    }

    /// What `read` finds in each registered instance of an IOKit class.
    private static func services<Value>(_ name: String, _ read: (io_object_t) -> Value?) -> [Value] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var values: [Value] = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let value = read(service) { values.append(value) }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return values
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// 64-bit byte counters of the Ethernet and Wi-Fi interfaces (`en*`), keyed
    /// by name. `getifaddrs` offers only 32-bit ones, which wrap every 4 GiB.
    private static func interfaceCounters() -> [String: (UInt64, UInt64)] {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, u_int(mib.count), nil, &length, nil, 0) == 0 else { return [:] }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, u_int(mib.count), &buffer, &length, nil, 0) == 0 else { return [:] }
        var counters: [String: (UInt64, UInt64)] = [:]
        var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= length,
                   let interface = name.withUnsafeMutableBufferPointer({
                       if_indextoname(UInt32(header.ifm_index), $0.baseAddress).map { String(cString: $0) }
                   }), interface.hasPrefix("en") {
                    let data = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self).ifm_data
                    counters[interface] = (data.ifi_ibytes, data.ifi_obytes)
                }
                offset += Int(header.ifm_msglen)
            }
        }
        return counters
    }

    /// Reads the internal battery; nil on Macs without one.
    private static func readBattery() -> BatteryStatus? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue
            let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue
            let onAC = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = (description[kIOPSIsChargingKey] as? NSNumber)?.boolValue == true
            let state: BatteryStatus.State = charging ? .charging : onAC ? .onAC : .discharging
            let minutes = (description[charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? NSNumber)?.intValue
            var fraction: Double?
            if let current, let maximum, maximum > 0 { fraction = min(1, max(0, current / maximum)) }
            let power = readPower(state: state)
            return BatteryStatus(fraction: fraction, state: state,
                                 minutesRemaining: state != .onAC ? minutes.flatMap { $0 >= 0 ? $0 : nil } : nil,
                                 usageWatts: power.usage, chargeWatts: power.charge)
        }
        return nil
    }

    private static func readPower(state: BatteryStatus.State) -> (usage: Double?, charge: Double?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }
        func number(_ key: String) -> Int64? { (property(service, key) as? NSNumber)?.int64Value }
        let telemetry = property(service, "PowerTelemetryData") as? [String: Any]
        return BatteryStatus.power(state: state,
                                   systemLoadMilliwatts: (telemetry?["SystemLoad"] as? NSNumber)?.int64Value,
                                   batteryMilliwatts: (telemetry?["BatteryPower"] as? NSNumber)?.int64Value,
                                   millivolts: number("Voltage"), milliamps: number("Amperage"))
    }
}
