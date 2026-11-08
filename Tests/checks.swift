extension Metrics {
    var networkBaselineTimeForCheck: TimeInterval? { prevNetTime }
}

let metrics = Metrics()
assert(metrics.cpu() == nil, "CPU first sample must be unavailable")
assert(metrics.network() == nil, "Network first sample must establish baseline")
let firstBaseline = metrics.networkBaselineTimeForCheck
Thread.sleep(forTimeInterval: 0.05)
assert(metrics.cpu().map { (0...1).contains($0) } == true)
let network = metrics.network()
assert(network != nil, "This Mac must expose en interfaces")
assert(metrics.networkBaselineTimeForCheck! > firstBaseline!, "Successful network sample must advance baseline")
assert(network!.downloadBytesPerSecond >= 0 && network!.uploadBytesPerSecond >= 0)
assert(metrics.ram().map { (0...1).contains($0) } == true)
assert(StatusViewController.percent(nil) == "—")
assert(StatusViewController.percent(0) == "0 %")
assert(StatusViewController.percent(1) == "100 %")
assert(StatusViewController.formatRate(nil) == "—")
assert(StatusViewController.formatRate(.nan) == "—")
assert(StatusViewController.formatRate(-1) == "—")
assert(StatusViewController.formatRate(0) == "0 B/s")
assert(StatusViewController.formatRate(1500).hasSuffix(" KB/s"))
assert(StatusViewController.formatRate(1_500_000).hasSuffix(" MB/s"))
assert(StatusViewController.formatRate(1_500_000_000).hasSuffix(" GB/s"))
let app = NSApplication.shared
let controller = StatusViewController()
controller.updateMetrics(cpu: nil, gpu: nil, ram: nil, net: nil)
assert(controller.preferredContentSize.width == 300)
assert(controller.preferredContentSize.height > 200)
controller.updateMetrics(cpu: 1, gpu: 1, ram: 1, net: NetworkRates(downloadBytesPerSecond: 999_999_999, uploadBytesPerSecond: 0))
controller.view.layoutSubtreeIfNeeded()
print("PASS: CPU/RAM live samples, network baseline regression, formatting, popover construction")
