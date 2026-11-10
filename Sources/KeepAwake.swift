import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac from idle sleep, like `caffeinate -i`: the display may still
/// go dark, and closing the lid still sleeps. macOS drops the assertion when
/// tinyStats quits, so nothing outlives the app.
final class KeepAwake {
    static let title = "Keep Awake"
    static let reason = "tinyStats: \(title)"
    static let offHelp = "Keep Awake: Off"
    static let onHelp = "Keep Awake: On. The display may still sleep; closing the lid still does."
    private var assertion: IOPMAssertionID?

    var isOn: Bool { assertion != nil }

    /// Returns the state actually reached; a refused assertion leaves it off.
    @discardableResult
    func set(_ on: Bool) -> Bool {
        if on, assertion == nil {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn), Self.reason as CFString, &id)
            if result == kIOReturnSuccess { assertion = id }
        } else if !on, let id = assertion {
            IOPMAssertionRelease(id)
            assertion = nil
        }
        return isOn
    }

    deinit { set(false) }
}
