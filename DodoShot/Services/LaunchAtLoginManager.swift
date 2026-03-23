import Foundation
import ServiceManagement

/// Manager for handling launch at login functionality
class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    /// Check if app is set to launch at login
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // For older macOS versions, we'll just return the stored setting
            return SettingsManager.shared.settings.launchAtStartup
        }
    }

    /// Enable or disable launch at login
    func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to \(enabled ? "enable" : "disable") launch at login: \(error)")
            }
        } else {
            // For older macOS versions, use the deprecated API
            let bundleId = Bundle.main.bundleIdentifier ?? "com.shutter.Shutter"
            SMLoginItemSetEnabled(bundleId as CFString, enabled)
        }
    }

    /// Sync the setting with the actual system state
    func syncWithSystemState() {
        if #available(macOS 13.0, *) {
            let isSystemEnabled = SMAppService.mainApp.status == .enabled
            if SettingsManager.shared.settings.launchAtStartup != isSystemEnabled {
                SettingsManager.shared.settings.launchAtStartup = isSystemEnabled
            }
        }
    }
}
