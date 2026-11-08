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
assert(MenuBarIndicators.compactRate(nil) == "—")
assert(MenuBarIndicators.compactRate(.nan) == "—")
assert(MenuBarIndicators.compactRate(-1) == "—")
assert(MenuBarIndicators.compactRate(0) == "0B")
assert(MenuBarIndicators.compactRate(500) == "500B")
assert(MenuBarIndicators.compactRate(1500).hasSuffix("K"))
assert(MenuBarIndicators.compactRate(999_500).hasSuffix("M"))
assert(MenuBarIndicators.compactRate(1_500_000).hasSuffix("M"))
assert(MenuBarIndicators.compactRate(1_500_000_000).hasSuffix("G"))
assert(MenuBarIndicators.compactRate(1_000_000_000_000) == "≥1T")
for value: Double? in [nil, 0, 0.07, 0.81, 1, .nan] {
    let image = MenuBarIndicators.image(cpu: value, gpu: value, ram: value, net: nil)
    assert(image.isTemplate && image.size == NSSize(width: 88, height: 22))
    assert(image.tiffRepresentation != nil, "Indicator must actually rasterize")
}
for rate in [0.0, 999, 999_499, 999_500, 999_499_999, 999_500_000, 999_499_999_999, 999_500_000_000, 1e12] {
    let text = MenuBarIndicators.compactRate(rate) as NSString
    assert(text.size(withAttributes: [.font: MenuBarIndicators.rateFont]).width <= 27,
           "Network label must fit in its reserved width")
}
print("PASS: menu bar templates rasterize; compact units, promotion, missing values and text widths")

assert(MenuBarIndicators.compactRate(999_500_000_000) == "1T")
for label in ["C", "G", "R"] {
    assert((label as NSString).size(withAttributes: [.font: MenuBarIndicators.labelFont]).width <= 9)
}
print("PASS: metric initials fit 9pt labels; worst-case rates fit tight 27pt field")

for locale in [Locale(identifier: "de_DE"), Locale(identifier: "en_US")] {
    for rate in [999.0, 1500, 999499, 999500, 9_940_000, 999_499_999, 999_499_999_999, 999_500_000_000, 1e12] {
        let text = MenuBarIndicators.compactRate(rate, locale: locale) as NSString
        let width = text.size(withAttributes: [.font: MenuBarIndicators.rateFont]).width
        let arrowWidth = ("↓" as NSString).size(withAttributes: [.font: MenuBarIndicators.rateFont]).width
        assert(width + arrowWidth + 2 <= 36, "Arrow and localized rate need at least 2pt separation")
    }
}
print("PASS: de_DE/en_US network labels fit 36pt block with 2pt arrow gap")
