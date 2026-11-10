import Foundation
import IOKit.pwr_mgt

/// Keeps the Mac from idle sleep, like `caffeinate -i`: the display may still
/// go dark, and closing the lid still sleeps. macOS drops the assertion when
/// tinyStats quits, so nothing outlives the app.
final class KeepAwake {
    static let title = "Keep Mac Awake"
    static let reason = "tinyStats: \(title)"
    static let offHelp = "Keeps your Mac from sleeping until you click again or quit tinyStats. The display can still turn off; closing the lid still puts the Mac to sleep."
    static let onHelp = "Your Mac stays awake. Click to let it sleep again."
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
