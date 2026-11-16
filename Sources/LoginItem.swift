import Foundation
import ServiceManagement

/// Open at Login as a system login item: listed under System Settings → General →
/// Login Items, where it can be removed too, so the state is always asked fresh.
enum LoginItem {
    static let title = "Open at Login"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Answers the state actually reached. When macOS wants the user to approve
    /// the item first, Login Items opens so the switch is right there.
    static func set(_ on: Bool) -> Bool {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
        } catch {
            NSLog("tinyStats: \(title) \(on ? "register" : "unregister") failed: \(error.localizedDescription)")
        }
        if on, service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        return isEnabled
    }
}
