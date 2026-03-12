import Foundation
import AppKit
import Combine

/// Manager for handling Screen Recording and Accessibility permissions
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    /// Whether screen recording permission is granted
    @Published var isScreenRecordingGranted: Bool = false

    /// Whether accessibility permission is granted
    @Published var isAccessibilityGranted: Bool = false

    /// Timer for checking permission status
    private var checkTimer: Timer?

    /// Flag to prevent repeated screen recording checks while system dialog is open
    private var isCheckingScreenRecording: Bool = false

    private init() {
        checkPermissions()
        // Don't auto-start monitoring - let the UI start it when needed
    }

    deinit {
        checkTimer?.invalidate()
    }

    // MARK: - Public Methods

    /// Check all permissions
    func checkPermissions() {
        checkScreenRecordingPermission()
        checkAccessibilityPermission()
    }

    /// Check screen recording permission
    func checkScreenRecordingPermission() {
        // Use CGPreflightScreenCaptureAccess which is the recommended API for
        // checking permission status without triggering the screen recording
        // indicator. This avoids the persistent recording notification (issue #6)
        // and is more reliable than the old capture-and-sample approach (issue #7).
        let hasAccess = CGPreflightScreenCaptureAccess()

        NSLog("[PermissionManager] Screen recording check (preflight): %@", hasAccess ? "true" : "false")

        DispatchQueue.main.async { [weak self] in
            if self?.isScreenRecordingGranted != hasAccess {
                NSLog("[PermissionManager] Screen recording changed: %@", hasAccess ? "true" : "false")
                self?.isScreenRecordingGranted = hasAccess
            }
        }
    }

    /// Check accessibility permission
    func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()

        // Also check with options for more detailed info
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        let trustedWithOptions = AXIsProcessTrustedWithOptions(options)

        NSLog("[PermissionManager] Accessibility AXIsProcessTrusted: %@, WithOptions: %@",
              trusted ? "true" : "false",
              trustedWithOptions ? "true" : "false")

        // Use the result from AXIsProcessTrustedWithOptions as it's more reliable
        var finalResult = trusted || trustedWithOptions

        // For DEBUG builds, allow bypassing accessibility check since ad-hoc signing
        // causes issues with macOS recognizing the approved app after rebuilds
        #if DEBUG
        if !finalResult {
            // Check if user has previously skipped (stored in UserDefaults)
            if UserDefaults.standard.bool(forKey: "debugAccessibilityBypassed") {
                NSLog("[PermissionManager] DEBUG: Accessibility bypassed by user preference")
                finalResult = true
            }
        }
        #endif

        DispatchQueue.main.async { [weak self] in
            if self?.isAccessibilityGranted != finalResult {
                NSLog("[PermissionManager] Accessibility changed to: %@", finalResult ? "true" : "false")
                self?.isAccessibilityGranted = finalResult
            }
        }
    }

    /// Bypass accessibility check for debug builds
    func bypassAccessibilityForDebug() {
        #if DEBUG
        UserDefaults.standard.set(true, forKey: "debugAccessibilityBypassed")
        isAccessibilityGranted = true
        NSLog("[PermissionManager] DEBUG: Accessibility check bypassed")
        #endif
    }

    /// Request screen recording permission
    func requestScreenRecordingPermission() {
        // Open System Settings to Screen Recording (macOS Ventura and later)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }

        // Fallback: try to trigger the system prompt by attempting a capture
        // This will show the permission dialog if not already granted
        CGRequestScreenCaptureAccess()
    }

    /// Request accessibility permission
    @discardableResult
    func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.async { [weak self] in
            self?.isAccessibilityGranted = trusted
        }
        return trusted
    }

    /// Open Screen Recording settings
    func openScreenRecordingSettings() {
        // Open System Settings directly to Screen Recording (macOS Sonoma)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Trigger the screen recording system prompt
    func triggerScreenRecordingPrompt() {
        CGRequestScreenCaptureAccess()
    }

    /// Open Accessibility settings
    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Show app in Finder (for drag and drop to settings)
    func showAppInFinder() {
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.selectFile(bundleURL.path, inFileViewerRootedAtPath: bundleURL.deletingLastPathComponent().path)
    }

    /// Restart the app
    func restartApp() {
        guard let bundlePath = Bundle.main.bundlePath as String? else { return }

        let script = """
            sleep 0.5
            open "\(bundlePath)"
            """

        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", script]
        try? task.run()

        NSApp.terminate(nil)
    }

    /// Start monitoring for permission changes
    func startMonitoring() {
        checkTimer?.invalidate()
        checkTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkPermissions()
        }
        RunLoop.main.add(checkTimer!, forMode: .common)
    }

    /// Stop monitoring
    func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    /// Whether all required permissions are granted
    var allPermissionsGranted: Bool {
        isScreenRecordingGranted && isAccessibilityGranted
    }
}
