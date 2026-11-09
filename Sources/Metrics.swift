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

final class Metrics {
    static let hasBattery = readBattery() != nil
    private static let diskSpaceInterval: TimeInterval = 30

    private var prevDisks: [UInt64: (read: UInt64, write: UInt64)]?
    private var prevDiskTime: TimeInterval?
    private var diskSpaceCache: (time: TimeInterval, value: DiskSpace?)?
    private var prevCPU: (user: UInt32, sys: UInt32, idle: UInt32, nice: UInt32)?
    private var prevNets: [String: (in: UInt64, out: UInt64)]?
    private(set) var prevNetTime: TimeInterval?

    func cpu() -> Double? {
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        defer {
            let u = info.cpu_ticks.0, s = info.cpu_ticks.1, i = info.cpu_ticks.2, n = info.cpu_ticks.3
            prevCPU = (u, s, i, n)
        }
        guard let p = prevCPU else { return nil }
        let du = Double(info.cpu_ticks.0 &- p.user)
        let ds = Double(info.cpu_ticks.1 &- p.sys)
        let di = Double(info.cpu_ticks.2 &- p.idle)
        let dn = Double(info.cpu_ticks.3 &- p.nice)
        let total = du + ds + di + dn
        return total > 0 ? (du + ds + dn) / total : nil
    }

    func gpu() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var busy = 0.0
        var found = false
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any],
                  let stats = props["PerformanceStatistics"] as? [String: Any],
                  let n = stats["Device Utilization %"] as? NSNumber else { continue }
            let raw = n.doubleValue
            guard raw.isFinite, raw >= 0, raw <= 100 else { continue }
            busy += raw / 100.0
            found = true
        }
        return found ? min(1.0, busy) : nil
    }

    func ram() -> Double? {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let total = ProcessInfo.processInfo.physicalMemory
        return total > 0 ? min(1.0, Double(used) / Double(total)) : nil
    }

    func network() -> NetworkRates? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            prevNets = nil
            prevNetTime = nil
            return nil
        }
        defer { freeifaddrs(ifaddr) }
        var current: [String: (in: UInt64, out: UInt64)] = [:]
        var ptr = ifaddr
        while let cur = ptr {
            defer { ptr = cur.pointee.ifa_next }
            let ifa = cur.pointee
            guard let namePtr = ifa.ifa_name,
                  let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_LINK),
                  let name = String(validatingUTF8: namePtr), name.hasPrefix("en") else { continue }
            if let data = ifa.ifa_data?.assumingMemoryBound(to: if_data.self) {
                current[name] = (UInt64(data.pointee.ifi_ibytes), UInt64(data.pointee.ifi_obytes))
            }
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard !current.isEmpty else {
            prevNets = nil
            prevNetTime = nil
            return nil
        }
        guard let prev = prevNets, let prevTime = prevNetTime, now > prevTime else {
            prevNets = current
            prevNetTime = now
            return nil
        }
        if Set(prev.keys) != Set(current.keys) {
            prevNets = current
            prevNetTime = now
            return nil
        }
        var counterDropped = false
        for name in current.keys {
            guard let p = prev[name], let c = current[name] else { continue }
            if c.in < p.in || c.out < p.out { counterDropped = true; break }
        }
        if counterDropped {
            prevNets = current
            prevNetTime = now
            return nil
        }
        let dt = now - prevTime
        guard dt > 0 else {
            prevNets = current
            prevNetTime = now
            return nil
        }
        var dIn = 0.0
        var dOut = 0.0
        for (name, c) in current {
            let p = prev[name]!
            dIn += Double(c.in - p.in)
            dOut += Double(c.out - p.out)
        }
        prevNets = current
        prevNetTime = now
        return NetworkRates(downloadBytesPerSecond: dIn / dt, uploadBytesPerSecond: dOut / dt)
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
            let minutesKey = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = (description[minutesKey] as? NSNumber)?.intValue
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
        func property(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        let telemetry = property("PowerTelemetryData") as? [String: Any]
        return BatteryStatus.power(state: state,
                                   systemLoadMilliwatts: (telemetry?["SystemLoad"] as? NSNumber)?.int64Value,
                                   batteryMilliwatts: (telemetry?["BatteryPower"] as? NSNumber)?.int64Value,
                                   millivolts: (property("Voltage") as? NSNumber)?.int64Value,
                                   milliamps: (property("Amperage") as? NSNumber)?.int64Value)
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

    /// Bytes per second across all block devices. A device appearing or
    /// disappearing starts a new baseline, so it never reads as a spike.
    func diskActivity() -> DiskRates? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var current: [UInt64: (read: UInt64, write: UInt64)] = [:]
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }
            var id: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &id) == KERN_SUCCESS,
                  let stats = IORegistryEntryCreateCFProperty(service, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                      .takeRetainedValue() as? [String: Any],
                  let read = stats["Bytes (Read)"] as? NSNumber, let write = stats["Bytes (Write)"] as? NSNumber else { continue }
            current[id] = (read.uint64Value, write.uint64Value)
        }
        let now = ProcessInfo.processInfo.systemUptime
        defer {
            prevDisks = current.isEmpty ? nil : current
            prevDiskTime = current.isEmpty ? nil : now
        }
        guard !current.isEmpty, let prev = prevDisks, let prevTime = prevDiskTime, now > prevTime,
              Set(prev.keys) == Set(current.keys) else { return nil }
        var read = 0.0, write = 0.0
        for (id, c) in current {
            guard let p = prev[id], c.read >= p.read, c.write >= p.write else { return nil }
            read += Double(c.read - p.read)
            write += Double(c.write - p.write)
        }
        return DiskRates(readBytesPerSecond: read / (now - prevTime), writeBytesPerSecond: write / (now - prevTime))
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
}
