import Foundation
import AppKit
import SwiftUI

// MARK: - Smart Capture Service

/// Captures an area, runs OCR, shows a prompt bar, and pastes the result into the
/// previously-active terminal.  This is the "one hotkey" flow for sending screenshots
/// + OCR text + user context straight into Claude Code.
@MainActor
class SmartCaptureService {
    static let shared = SmartCaptureService()

    private var previousApp: NSRunningApplication?
    private var capturedImage: NSImage?
    private var ocrResult: OCRResult?
    private var imagePath: String?
    private var promptWindow: NSPanel?
    private var captureWindows: [NSWindow] = []

    private init() {}

    // MARK: - Public API

    func startSmartCapture() {
        previousApp = NSWorkspace.shared.frontmostApplication

        guard let screen = NSScreen.main else { return }

        closeCaptureWindows()

        let window = createCaptureOverlayWindow(for: screen)
        let contentView = AreaSelectionView(
            onComplete: { [weak self] rect in
                self?.captureAreaForSmartCapture(rect: rect, screen: screen)
            },
            onCancel: { [weak self] in
                self?.cancelCapture()
            }
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        captureWindows.append(window)
    }

    // MARK: - Capture

    private func captureAreaForSmartCapture(rect: CGRect, screen: NSScreen) {
        // Hide capture windows first
        for window in captureWindows {
            window.orderOut(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }

            let screenRect = CGRect(
                x: rect.origin.x + screen.frame.origin.x,
                y: rect.origin.y + screen.frame.origin.y,
                width: rect.width,
                height: rect.height
            )

            guard let cgImage = CGWindowListCreateImage(
                screenRect,
                .optionOnScreenBelowWindow,
                kCGNullWindowID,
                [.bestResolution]
            ) else {
                self.closeCaptureWindows()
                return
            }

            let nsImage = NSImage(cgImage: cgImage, size: rect.size)
            self.closeCaptureWindows()
            self.handleCaptureComplete(image: nsImage)
        }
    }

    private func handleCaptureComplete(image: NSImage) {
        capturedImage = image

        // Save to /tmp
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let path = "/tmp/lucida-capture-\(timestamp).png"
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
        imagePath = path

        // Run OCR
        let format = SettingsManager.shared.settings.ocrOutputFormat
        OCRService.shared.extractText(from: image, format: format, forceType: nil) { [weak self] result in
            switch result {
            case .success(let ocrResult):
                self?.ocrResult = ocrResult
                self?.showPromptBar()
            case .failure:
                // Even if OCR fails, still show prompt bar (image path is useful on its own)
                self?.ocrResult = nil
                self?.showPromptBar()
            }
        }
    }

    // MARK: - Prompt Bar

    private func showPromptBar() {
        guard let screen = NSScreen.main else { return }

        let panelWidth: CGFloat = 440
        let panelHeight: CGFloat = 48

        let x = screen.frame.midX - panelWidth / 2
        let y = screen.visibleFrame.minY + 80

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false

        let detectedType = ocrResult?.detectedType ?? .prose

        let promptView = SmartCapturePromptView(
            detectedType: detectedType,
            onSubmit: { [weak self] prompt in
                self?.submitPrompt(prompt)
            },
            onCancel: { [weak self] in
                self?.cancelPrompt()
            }
        )

        let hostingView = NSHostingView(rootView: promptView)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        panel.contentView = hostingView

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        promptWindow = panel
    }

    // MARK: - Submit / Cancel

    func submitPrompt(_ prompt: String) {
        // Dismiss the prompt bar
        dismissPromptWindow()

        let message: String
        if prompt.isEmpty {
            // No prompt: just paste formatted OCR text (or image path if OCR failed)
            if let ocrResult = ocrResult {
                message = ocrResult.formattedText
            } else if let path = imagePath {
                message = path
            } else {
                return
            }
        } else {
            // With prompt: compose image path + OCR text + user context
            var parts: [String] = []
            if let path = imagePath {
                parts.append(path)
            }
            if let ocrResult = ocrResult {
                parts.append("")
                parts.append(ocrResult.formattedText)
            }
            parts.append("")
            parts.append(prompt)
            message = parts.joined(separator: "\n")
        }

        // Put on clipboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message, forType: .string)

        // Re-activate previous app and paste
        if let app = previousApp {
            app.activate(options: [])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let source = CGEventSource(stateID: .hidSystemState)

                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // V
                keyDown?.flags = .maskCommand
                keyDown?.post(tap: .cgAnnotatedSessionEventTap)

                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
                keyUp?.flags = .maskCommand
                keyUp?.post(tap: .cgAnnotatedSessionEventTap)
            }
        }

        resetState()
    }

    private func cancelPrompt() {
        dismissPromptWindow()
        // Clean up temp file
        if let path = imagePath {
            try? FileManager.default.removeItem(atPath: path)
        }
        resetState()
    }

    // MARK: - Helpers

    private func dismissPromptWindow() {
        if let panel = promptWindow {
            panel.alphaValue = 0
            panel.close()
            promptWindow = nil
        }
    }

    private func resetState() {
        capturedImage = nil
        ocrResult = nil
        imagePath = nil
        previousApp = nil
    }

    private func cancelCapture() {
        closeCaptureWindows()
        resetState()
    }

    private func closeCaptureWindows() {
        for window in captureWindows {
            window.close()
        }
        captureWindows.removeAll()
    }

    private func createCaptureOverlayWindow(for screen: NSScreen) -> CaptureWindow {
        let window = CaptureWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.onEscape = { [weak self] in
            self?.cancelCapture()
        }

        return window
    }
}
