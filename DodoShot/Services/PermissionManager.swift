import Foundation
import AppKit
import Combine
import ScreenCaptureKit

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

    /// Check screen recording permission using ScreenCaptureKit.
    /// SCShareableContent provides accurate, real-time permission status
    /// unlike CGPreflightScreenCaptureAccess which caches per-process.
    func checkScreenRecordingPermission() {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            let hasAccess = content != nil && error == nil
            DispatchQueue.main.async {
                if self?.isScreenRecordingGranted != hasAccess {
                    self?.isScreenRecordingGranted = hasAccess
                }
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

        // Ad-hoc signed apps can't be reliably detected by AXIsProcessTrusted
        // even when the user has enabled them in System Settings. Allow bypass.
        if !finalResult {
            if UserDefaults.standard.bool(forKey: "accessibilityBypassed") {
                finalResult = true
            }
        }

        DispatchQueue.main.async { [weak self] in
            if self?.isAccessibilityGranted != finalResult {
                NSLog("[PermissionManager] Accessibility changed to: %@", finalResult ? "true" : "false")
                self?.isAccessibilityGranted = finalResult
            }
        }
    }

    /// Bypass accessibility check (ad-hoc signed apps can't be reliably detected)
    func bypassAccessibility() {
        UserDefaults.standard.set(true, forKey: "accessibilityBypassed")
        isAccessibilityGranted = true
    }

    /// Request screen recording permission
    func requestScreenRecordingPermission() {
        // Open System Settings to Screen & System Audio Recording via URL scheme.
        // This doesn't require the apple-events entitlement (unlike AppleScript).
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }

        // Also trigger the system prompt
        CGRequestScreenCaptureAccess()
    }

    /// Reset bypass flag and re-prompt for accessibility
    func resetAndRequestAccessibility() {
        // Clear the bypass flag so we re-check properly
        UserDefaults.standard.removeObject(forKey: "accessibilityBypassed")

        // Note: tccutil reset requires admin privileges on macOS Sonoma+ and
        // silently fails without them, so we skip it and just re-prompt.
        requestAccessibilityPermission()
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
        requestScreenRecordingPermission()
    }

    /// Trigger the screen recording system prompt
    func triggerScreenRecordingPrompt() {
        CGRequestScreenCaptureAccess()
    }

    /// Open Accessibility settings in Privacy & Security
    func openAccessibilitySettings() {
        // System Settings doesn't reliably navigate between Privacy sub-panes
        // when already open (e.g. stuck on Screen Recording from step 1).
        // Kill it first, then reopen at the Accessibility pane.
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
            .forEach { $0.terminate() }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
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
