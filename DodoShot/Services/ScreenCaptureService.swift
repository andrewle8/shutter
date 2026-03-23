import Foundation
import AppKit
import Combine

@MainActor
class ScreenCaptureService: ObservableObject {
    static let shared = ScreenCaptureService()

    @Published var recentCaptures: [Screenshot] = []
    @Published var currentCapture: Screenshot?
    @Published var isCapturing = false

    private var captureWindows: [NSWindow] = []
    private var previousApp: NSRunningApplication?
    private var autoPasteAfterCapture = false
    private var ocrPasteAfterCapture = false
    private var ocrForceType: DetectedContentType? = nil
    /// Per-screen frozen images captured before showing the selection overlay
    private var frozenScreenImages: [NSScreen: CGImage] = [:]

    private init() {}

    // MARK: - Public Methods

    func startCapture(type: CaptureType) {
        // Prevent double-start
        guard !isCapturing else { return }

        // Save the frontmost app BEFORE any overlay windows appear
        previousApp = NSWorkspace.shared.frontmostApplication
        isCapturing = true

        switch type {
        case .area:
            startAreaCapture()
        case .window:
            startWindowCapture()
        case .fullscreen:
            showScreenPickerOrCapture()
        }
    }

    func clearRecents() {
        recentCaptures.removeAll()
    }

    /// Capture an area and auto-paste into the previously-active app
    func startCaptureAndPaste(type: CaptureType) {
        autoPasteAfterCapture = true
        startCapture(type: type)
    }

    /// Start OCR capture, extract text, and paste into the previously-active app
    func startOCRCaptureAndPaste() {
        ocrPasteAfterCapture = true
        startOCRCapture()
    }

    /// Capture area, OCR as error/log, copy formatted text and paste
    func startErrorCapture() {
        ocrForceType = .errorLog
        ocrPasteAfterCapture = true
        startOCRCapture()
    }

    /// Capture area, OCR as code block, copy formatted text and paste
    func startCodeCapture() {
        ocrForceType = .code
        ocrPasteAfterCapture = true
        startOCRCapture()
    }

    /// Capture area, save to /tmp, paste file path into terminal
    func startCaptureForClaude() {
        previousApp = NSWorkspace.shared.frontmostApplication
        captureForClaudeMode = true
        startCapture(type: .area)
    }

    /// All-in-one capture: drag=area, click=window, Return=fullscreen
    func startUnifiedCapture() {
        previousApp = NSWorkspace.shared.frontmostApplication
        isCapturing = true

        closeCaptureWindows()
        frozenScreenImages.removeAll()

        let freezeEnabled = SettingsManager.shared.settings.freezeScreenBeforeCapture
        let screens = NSScreen.screens

        if freezeEnabled {
            for screen in screens {
                if let cgImage = CGWindowListCreateImage(
                    screen.frame,
                    .optionOnScreenOnly,
                    kCGNullWindowID,
                    [.bestResolution]
                ) {
                    frozenScreenImages[screen] = cgImage
                }
            }
        }

        for screen in screens {
            let window = createCaptureOverlayWindow(for: screen)
            let frozenImage = frozenScreenImages[screen]
            let contentView = AreaSelectionView(
                onComplete: { [weak self] rect in
                    self?.captureArea(rect: rect, screen: screen)
                },
                onCancel: { [weak self] in
                    self?.cancelCapture()
                },
                frozenBackground: frozenImage,
                onWindowClick: { [weak self] windowRect in
                    self?.captureArea(rect: windowRect, screen: screen)
                },
                onFullscreen: { [weak self] in
                    self?.closeCaptureWindows()
                    self?.captureFullscreen(screen: screen)
                }
            )

            window.contentView = NSHostingView(rootView: contentView)
            window.makeKeyAndOrderFront(nil)
            captureWindows.append(window)
        }
    }

    /// Re-capture the same area as the last area capture
    func recaptureLastArea() {
        guard let rect = lastCaptureRect, let screen = lastCaptureScreen else {
            startCapture(type: .area)
            return
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        isCapturing = true
        captureArea(rect: rect, screen: screen)
    }

    private var captureForClaudeMode = false
    private var lastCaptureRect: CGRect?

    /// Reset all capture mode flags to prevent state leaking between captures
    private func resetCaptureFlags() {
        autoPasteAfterCapture = false
        ocrPasteAfterCapture = false
        captureForClaudeMode = false
        ocrForceType = nil
    }
    private var lastCaptureScreen: NSScreen?

    /// Start scrolling OCR: select an area, then auto-scroll and OCR each frame,
    /// deduplicating overlapping text between frames.
    func startScrollingOCR() {
        previousApp = NSWorkspace.shared.frontmostApplication
        isCapturing = true

        guard let screen = NSScreen.main else {
            isCapturing = false
            return
        }

        let window = createCaptureOverlayWindow(for: screen)
        let contentView = AreaSelectionView(
            onComplete: { [weak self] rect in
                self?.beginScrollingOCRForArea(rect: rect, screen: screen)
            },
            onCancel: { [weak self] in
                self?.cancelCapture()
            }
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        captureWindows.append(window)
    }

    /// Capture the frontmost non-Lucida window immediately (no picker UI).
    /// This is the default behaviour for the window capture hotkey.
    func captureActiveWindow() {
        previousApp = NSWorkspace.shared.frontmostApplication
        isCapturing = true

        let windows = WindowInfo.getVisibleWindows()
        if let frontmost = windows.first(where: { $0.ownerName != "Lucida" }) {
            captureWindow(frontmost)
        } else if let first = windows.first {
            captureWindow(first)
        } else {
            isCapturing = false
        }
    }

    /// Show the interactive window picker overlay so the user can choose a window.
    func showWindowPickerUI() {
        previousApp = NSWorkspace.shared.frontmostApplication
        isCapturing = true

        let windows = WindowInfo.getVisibleWindows()
        if windows.isEmpty {
            isCapturing = false
            return
        }
        showWindowPicker(windows: windows)
    }

    /// Capture all screens into a single image
    func captureAllScreens() {
        isCapturing = true

        // Small delay to ensure menu bar closes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }

            // CGRect.infinite captures the entire virtual display space (all monitors)
            guard let cgImage = CGWindowListCreateImage(
                CGRect.infinite,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            ) else {
                self.isCapturing = false
                return
            }

            // Compute the bounding rect of all screens in point space
            let screens = NSScreen.screens
            let union = screens.reduce(CGRect.null) { $0.union($1.frame) }
            let nsImage = NSImage(cgImage: cgImage, size: union.size)
            self.completeCapture(image: nsImage, type: .fullscreen)
        }
    }

    /// Show a screen picker when multiple monitors are connected, or capture directly on single-monitor setups.
    func showScreenPickerOrCapture() {
        let screens = NSScreen.screens
        if screens.count <= 1 {
            // Single monitor -- capture immediately
            captureFullscreen()
            return
        }

        // Multiple monitors -- show picker
        showScreenPickerModal()
    }

    func startScrollingCapture() {
        previousApp = NSWorkspace.shared.frontmostApplication
        isCapturing = true

        // Show area selection, then hand the selected rect to ScrollingCaptureService
        closeCaptureWindows()

        let screens = NSScreen.screens
        for screen in screens {
            let window = createCaptureOverlayWindow(for: screen)
            let contentView = AreaSelectionView(
                onComplete: { [weak self] rect in
                    self?.beginScrollingCaptureForArea(rect: rect, screen: screen)
                },
                onCancel: { [weak self] in
                    self?.cancelCapture()
                }
            )

            window.contentView = NSHostingView(rootView: contentView)
            window.makeKeyAndOrderFront(nil)
            captureWindows.append(window)
        }
    }

    /// Show the timed capture modal for selecting delay
    func showTimedCaptureModal() {
        guard let screen = NSScreen.main else { return }

        let windowSize = NSSize(width: 280, height: 200)
        let windowOrigin = NSPoint(
            x: (screen.visibleFrame.width - windowSize.width) / 2 + screen.visibleFrame.origin.x,
            y: (screen.visibleFrame.height - windowSize.height) / 2 + screen.visibleFrame.origin.y
        )

        let window = NSWindow(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Timed capture"
        window.level = .floating
        window.isReleasedWhenClosed = false

        let modalView = TimedCaptureModalView(
            onSelect: { [weak self] seconds in
                window.close()
                self?.startTimedCapture(delay: Double(seconds))
            },
            onCancel: {
                window.close()
            }
        )

        window.contentView = NSHostingView(rootView: modalView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Start a timed fullscreen capture after a delay (useful for capturing menus/dropdowns)
    func startTimedCapture(delay: Double) {
        isCapturing = true

        // Show a countdown notification
        showTimedCaptureCountdown(seconds: Int(delay))

        // Capture after the delay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.captureFullscreen()
        }
    }

    private func showTimedCaptureCountdown(seconds: Int) {
        // Show a small floating countdown window
        guard let screen = NSScreen.main else { return }

        let windowSize = NSSize(width: 120, height: 120)
        let windowOrigin = NSPoint(
            x: (screen.visibleFrame.width - windowSize.width) / 2 + screen.visibleFrame.origin.x,
            y: (screen.visibleFrame.height - windowSize.height) / 2 + screen.visibleFrame.origin.y
        )

        let window = NSWindow(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let countdownView = TimedCaptureCountdownView(seconds: seconds) {
            window.close()
        }

        window.contentView = NSHostingView(rootView: countdownView)
        window.orderFront(nil)
    }

    func copyToClipboard(_ screenshot: Screenshot) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([screenshot.image])
    }

    /// Start OCR capture - select an area and extract text
    func startOCRCapture() {
        isCapturing = true
        previousApp = NSWorkspace.shared.frontmostApplication

        guard let screen = NSScreen.main else {
            isCapturing = false
            return
        }

        let window = createCaptureOverlayWindow(for: screen)
        let contentView = AreaSelectionView(
            onComplete: { [weak self] rect in
                self?.captureAreaForOCR(rect: rect, screen: screen)
            },
            onCancel: { [weak self] in
                self?.cancelCapture()
            }
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        captureWindows.append(window)
    }

    private func captureAreaForOCR(rect: CGRect, screen: NSScreen) {
        // Hide capture windows first
        for window in captureWindows {
            window.orderOut(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self else { return }

            // Convert to global display coordinates
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
                self.isCapturing = false
                self.closeCaptureWindows()
                return
            }

            // Use rect.size (points) not cgImage size (pixels) for correct Retina display
            let nsImage = NSImage(cgImage: cgImage, size: rect.size)
            self.closeCaptureWindows()
            self.isCapturing = false

            // Perform OCR with format settings
            let shouldPaste = self.ocrPasteAfterCapture
            let forceType = self.ocrForceType
            self.ocrPasteAfterCapture = false
            self.ocrForceType = nil

            let format = SettingsManager.shared.settings.ocrOutputFormat

            OCRService.shared.extractText(
                from: nsImage,
                format: format,
                forceType: forceType
            ) { result in
                switch result {
                case .success(let ocrResult):
                    // If LLM cleanup is enabled, post-process the text
                    let settings = SettingsManager.shared.settings
                    if settings.ocrLLMCleanup {
                        Task {
                            let available = await OCRPostProcessor.shared.isOllamaAvailable()
                            if available {
                                // Run cleanup with 10s timeout
                                let cleaned = await withTaskGroup(of: String?.self) { group -> String in
                                    group.addTask {
                                        await OCRPostProcessor.shared.cleanup(
                                            text: ocrResult.formattedText,
                                            detectedType: ocrResult.detectedType
                                        )
                                    }
                                    group.addTask {
                                        try? await Task.sleep(nanoseconds: 10_000_000_000)
                                        return nil  // timeout sentinel
                                    }
                                    // Take whichever finishes first
                                    var result: String = ocrResult.formattedText
                                    for await value in group {
                                        if let v = value {
                                            result = v
                                            group.cancelAll()
                                            break
                                        } else {
                                            // Timeout hit, cancel cleanup and use original
                                            group.cancelAll()
                                            break
                                        }
                                    }
                                    return result
                                }
                                let cleanedResult = OCRResult(
                                    rawText: ocrResult.rawText,
                                    formattedText: cleaned,
                                    detectedType: ocrResult.detectedType,
                                    detectedLanguage: ocrResult.detectedLanguage,
                                    lineCount: ocrResult.lineCount
                                )
                                DispatchQueue.main.async {
                                    OCRService.shared.copyToClipboard(cleanedResult.formattedText)
                                    if shouldPaste {
                                        self.pasteToFrontApp()
                                    } else {
                                        self.showOCRResult(ocrResult: cleanedResult)
                                    }
                                }
                            } else {
                                // Ollama not running, use original
                                DispatchQueue.main.async {
                                    OCRService.shared.copyToClipboard(ocrResult.formattedText)
                                    if shouldPaste {
                                        self.pasteToFrontApp()
                                    } else {
                                        self.showOCRResult(ocrResult: ocrResult)
                                    }
                                }
                            }
                        }
                    } else {
                        OCRService.shared.copyToClipboard(ocrResult.formattedText)
                        if shouldPaste {
                            self.pasteToFrontApp()
                        } else {
                            self.showOCRResult(ocrResult: ocrResult)
                        }
                    }
                case .failure(let error):
                    self.showOCRError(error: error)
                }
            }
        }
    }

    private func showOCRResult(ocrResult: OCRResult) {
        guard let screen = NSScreen.main else { return }

        let windowSize = NSSize(width: 460, height: 340)
        let windowOrigin = NSPoint(
            x: (screen.visibleFrame.width - windowSize.width) / 2 + screen.visibleFrame.origin.x,
            y: (screen.visibleFrame.height - windowSize.height) / 2 + screen.visibleFrame.origin.y
        )

        let window = NSWindow(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Extracted text"
        window.level = .floating
        window.isReleasedWhenClosed = false

        let resultView = OCRResultView(ocrResult: ocrResult) {
            window.close()
        }

        window.contentView = NSHostingView(rootView: resultView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOCRError(error: Error) {
        let alert = NSAlert()
        alert.messageText = L10n.OCR.failed
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }

    func saveToFile(_ screenshot: Screenshot, url: URL? = nil) {
        let saveURL = url ?? getDefaultSaveURL()
        let settings = SettingsManager.shared.settings

        // Ensure save directory exists
        let saveDirectory = saveURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: saveDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
            } catch {
                print("Failed to create screenshots directory: \(error)")
            }
        }

        // Use ImageFormatAnalyzer for intelligent format selection
        if let savedURL = ImageFormatAnalyzer.shared.saveImage(
            screenshot.image,
            to: saveURL,
            format: settings.imageFormat,
            jpgQuality: settings.jpgQuality
        ) {
            print("Screenshot saved to: \(savedURL.path)")
        }
    }

    // MARK: - Area Capture

    private func startAreaCapture() {
        // Close any existing capture windows first
        closeCaptureWindows()
        frozenScreenImages.removeAll()

        let freezeEnabled = SettingsManager.shared.settings.freezeScreenBeforeCapture

        // Get all screens for multi-monitor support
        let screens = NSScreen.screens

        // If freeze is enabled, capture each screen BEFORE showing overlays
        if freezeEnabled {
            for screen in screens {
                if let cgImage = CGWindowListCreateImage(
                    screen.frame,
                    .optionOnScreenOnly,
                    kCGNullWindowID,
                    [.bestResolution]
                ) {
                    frozenScreenImages[screen] = cgImage
                }
            }
        }

        // Create overlay windows for each screen
        for screen in screens {
            let window = createCaptureOverlayWindow(for: screen)
            let frozenImage = frozenScreenImages[screen]
            let contentView = AreaSelectionView(
                onComplete: { [weak self] rect in
                    self?.captureArea(rect: rect, screen: screen)
                },
                onCancel: { [weak self] in
                    self?.cancelCapture()
                },
                frozenBackground: frozenImage
            )

            window.contentView = NSHostingView(rootView: contentView)
            window.makeKeyAndOrderFront(nil)
            captureWindows.append(window)
        }
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

    private func captureArea(rect: CGRect, screen: NSScreen) {
        // Check if we have a frozen image to crop from
        let frozenImage = frozenScreenImages[screen]

        // Hide all capture windows first
        for window in captureWindows {
            window.orderOut(nil)
        }

        // Round the rect to integer values to avoid fractional pixel issues
        let roundedRect = CGRect(
            x: round(rect.origin.x),
            y: round(rect.origin.y),
            width: round(rect.width),
            height: round(rect.height)
        )

        // Save the rect and screen for re-capture
        self.lastCaptureRect = roundedRect
        self.lastCaptureScreen = screen

        if let frozenImage = frozenImage {
            // Frozen mode: crop directly from the pre-captured frozen image
            NSLog("[ScreenCaptureService] captureArea (frozen) - input rect: %@, screen: %@",
                  NSStringFromRect(rect), NSStringFromRect(screen.frame))

            let scaleFactor = screen.backingScaleFactor

            // Convert point-based rect to pixel-based rect for cropping the CGImage
            let cropRect = CGRect(
                x: roundedRect.origin.x * scaleFactor,
                y: roundedRect.origin.y * scaleFactor,
                width: roundedRect.width * scaleFactor,
                height: roundedRect.height * scaleFactor
            )

            guard let croppedCGImage = frozenImage.cropping(to: cropRect) else {
                NSLog("[ScreenCaptureService] captureArea (frozen) - cropping failed")
                isCapturing = false
                closeCaptureWindows()
                frozenScreenImages.removeAll()
                return
            }

            NSLog("[ScreenCaptureService] captureArea (frozen) - cropped size: %d x %d, expected points: %.0f x %.0f",
                  croppedCGImage.width, croppedCGImage.height, roundedRect.width, roundedRect.height)

            let nsImage = NSImage(cgImage: croppedCGImage, size: roundedRect.size)
            closeCaptureWindows()
            frozenScreenImages.removeAll()
            completeCapture(image: nsImage, type: .area)
        } else {
            // Live mode: capture from screen after hiding overlay windows
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }

                let scaleFactor = screen.backingScaleFactor
                NSLog("[ScreenCaptureService] captureArea - input rect: %@, screen: %@, scaleFactor: %.1f",
                      NSStringFromRect(rect), NSStringFromRect(screen.frame), scaleFactor)

                let screenRect = CGRect(
                    x: roundedRect.origin.x + screen.frame.origin.x,
                    y: roundedRect.origin.y + screen.frame.origin.y,
                    width: roundedRect.width,
                    height: roundedRect.height
                )

                NSLog("[ScreenCaptureService] captureArea - screenRect for capture: %@", NSStringFromRect(screenRect))

                guard let cgImage = CGWindowListCreateImage(
                    screenRect,
                    .optionOnScreenBelowWindow,
                    kCGNullWindowID,
                    [.bestResolution]
                ) else {
                    NSLog("[ScreenCaptureService] captureArea - CGWindowListCreateImage failed")
                    self.isCapturing = false
                    self.closeCaptureWindows()
                    return
                }

                NSLog("[ScreenCaptureService] captureArea - cgImage size: %d x %d, expected points: %.0f x %.0f",
                      cgImage.width, cgImage.height, roundedRect.width, roundedRect.height)

                let nsImage = NSImage(cgImage: cgImage, size: roundedRect.size)
                self.closeCaptureWindows()
                self.completeCapture(image: nsImage, type: .area)
            }
        }
    }

    // MARK: - Window Capture

    private func startWindowCapture() {
        // Get windows using CGWindowList API (no permission dialog)
        let windows = WindowInfo.getVisibleWindows()

        if windows.isEmpty {
            print("No windows found for capture")
            isCapturing = false
            return
        }

        // Auto-capture the frontmost window (first in the list, excluding Lucida itself)
        if let frontmostWindow = windows.first(where: { $0.ownerName != "Lucida" }) {
            captureWindow(frontmostWindow)
        } else if let firstWindow = windows.first {
            // Fallback to first window if all are Lucida windows
            captureWindow(firstWindow)
        } else {
            isCapturing = false
        }
    }

    private func showWindowPicker(windows: [WindowInfo]) {
        guard let screen = NSScreen.main else { return }

        let window = createCaptureOverlayWindow(for: screen)
        let contentView = WindowSelectionView(
            windows: windows,
            onSelect: { [weak self] selectedWindow in
                self?.captureWindow(selectedWindow)
            },
            onCancel: { [weak self] in
                self?.cancelCapture()
            }
        )

        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        captureWindows.append(window)
    }

    private func captureWindow(_ windowInfo: WindowInfo) {
        closeCaptureWindows()

        let includeShadow = SettingsManager.shared.settings.captureWindowShadow
        var imageOptions: CGWindowImageOption = [.bestResolution]
        if !includeShadow {
            imageOptions.insert(.boundsIgnoreFraming)
        }

        guard let cgImage = CGWindowListCreateImage(
            windowInfo.frame,
            .optionIncludingWindow,
            windowInfo.windowID,
            imageOptions
        ) else {
            isCapturing = false
            return
        }

        // Use windowInfo.frame.size (points) not cgImage size (pixels) for correct Retina display
        let nsImage = NSImage(cgImage: cgImage, size: windowInfo.frame.size)
        completeCapture(image: nsImage, type: .window)
    }

    // MARK: - Scrolling Capture

    private func beginScrollingCaptureForArea(rect: CGRect, screen: NSScreen) {
        // Hide capture overlay windows before starting the scroll loop
        for window in captureWindows {
            window.orderOut(nil)
        }

        // Short delay so overlays are fully hidden
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.closeCaptureWindows()

            ScrollingCaptureService.shared.startAreaScrollingCapture(rect: rect, screen: screen) { [weak self] image in
                guard let self = self else { return }
                if let image = image {
                    self.completeCapture(image: image, type: .area)
                } else {
                    self.isCapturing = false
                }
            }
        }
    }

    // MARK: - Scrolling OCR

    private func beginScrollingOCRForArea(rect: CGRect, screen: NSScreen) {
        // Hide capture overlay windows
        for window in captureWindows {
            window.orderOut(nil)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.closeCaptureWindows()

            // Convert to global display coordinates
            let globalRect = CGRect(
                x: round(rect.origin.x) + screen.frame.origin.x,
                y: round(rect.origin.y) + screen.frame.origin.y,
                width: round(rect.width),
                height: round(rect.height)
            )

            // Scrolling OCR loop
            self.runScrollingOCRLoop(
                rect: globalRect,
                pointSize: rect.size,
                accumulatedText: "",
                frameCount: 0,
                maxFrames: 20,
                previousText: ""
            )
        }
    }

    private func runScrollingOCRLoop(
        rect: CGRect,
        pointSize: CGSize,
        accumulatedText: String,
        frameCount: Int,
        maxFrames: Int,
        previousText: String
    ) {
        guard frameCount < maxFrames else {
            finishScrollingOCR(text: accumulatedText)
            return
        }

        // Capture the area
        guard let cgImage = CGWindowListCreateImage(
            rect,
            .optionOnScreenBelowWindow,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            finishScrollingOCR(text: accumulatedText)
            return
        }

        let nsImage = NSImage(cgImage: cgImage, size: pointSize)
        let format = SettingsManager.shared.settings.ocrOutputFormat

        OCRService.shared.extractText(from: nsImage, format: format, forceType: nil) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let ocrResult):
                let newText = ocrResult.rawText

                // Check if content stopped changing (scroll reached the end)
                // Use similarity check instead of exact match since OCR output varies slightly
                if self.ocrTextIsSame(newText, previousText) {
                    self.finishScrollingOCR(text: accumulatedText)
                    return
                }

                // Merge with deduplication
                let merged = OCRService.mergeScrollingOCRText(
                    existing: accumulatedText,
                    newText: newText
                )

                // Scroll down
                let scrollPixels = Int32(rect.height * 0.8)
                self.sendScrollEvent(amount: -scrollPixels, rect: rect)

                // Wait for scroll to settle, then capture next frame
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.runScrollingOCRLoop(
                        rect: rect,
                        pointSize: pointSize,
                        accumulatedText: merged,
                        frameCount: frameCount + 1,
                        maxFrames: maxFrames,
                        previousText: newText
                    )
                }

            case .failure:
                // If OCR fails on a frame, finish with what we have
                self.finishScrollingOCR(text: accumulatedText)
            }
        }
    }

    private func sendScrollEvent(amount: Int32, rect: CGRect) {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: amount, wheel2: 0, wheel3: 0)
        event?.location = CGPoint(x: rect.midX, y: rect.midY)
        event?.post(tap: .cgSessionEventTap)
    }

    /// Check if two OCR text outputs represent the same content.
    /// Uses line-level similarity (>90% of lines match) to tolerate minor OCR variance.
    private func ocrTextIsSame(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return a.isEmpty && b.isEmpty }

        let aLines = a.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let bLines = b.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }

        // If line counts differ significantly, they're different
        if abs(aLines.count - bLines.count) > max(1, aLines.count / 5) {
            return false
        }

        // Compare overlapping lines
        let count = min(aLines.count, bLines.count)
        guard count > 0 else { return true }

        var matchingLines = 0
        for i in 0..<count {
            if aLines[i] == bLines[i] {
                matchingLines += 1
            }
        }

        return Double(matchingLines) / Double(count) > 0.9
    }

    private func finishScrollingOCR(text: String) {
        isCapturing = false

        guard !text.isEmpty else {
            showOCRError(error: OCRError.noTextFound)
            return
        }

        let lines = text.components(separatedBy: "\n")
        let result = OCRResult(
            rawText: text,
            formattedText: text,
            detectedType: .prose,
            detectedLanguage: nil,
            lineCount: lines.count
        )

        OCRService.shared.copyToClipboard(result.formattedText)

        if ocrPasteAfterCapture {
            ocrPasteAfterCapture = false
            pasteToFrontApp()
        } else {
            showOCRResult(ocrResult: result)
        }
    }

    // MARK: - Fullscreen Capture

    /// Capture a single screen. Pass nil to capture the main screen.
    func captureFullscreen(screen: NSScreen? = nil) {
        let targetScreen = screen ?? NSScreen.main
        guard let targetScreen = targetScreen else {
            isCapturing = false
            return
        }

        isCapturing = true

        // Small delay to ensure menu bar closes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let cgImage = CGWindowListCreateImage(
                targetScreen.frame,
                .optionOnScreenOnly,
                kCGNullWindowID,
                [.bestResolution]
            ) else {
                self?.isCapturing = false
                return
            }

            // Use screen.frame.size (points) not cgImage size (pixels) for correct Retina display
            let nsImage = NSImage(cgImage: cgImage, size: targetScreen.frame.size)
            self?.completeCapture(image: nsImage, type: .fullscreen)
        }
    }

    /// Show a modal picker listing each connected screen plus an "All Screens" option.
    private func showScreenPickerModal() {
        guard let mainScreen = NSScreen.main else { return }

        let windowSize = NSSize(width: 320, height: CGFloat(60 + NSScreen.screens.count * 48 + 48 + 24))
        let windowOrigin = NSPoint(
            x: (mainScreen.visibleFrame.width - windowSize.width) / 2 + mainScreen.visibleFrame.origin.x,
            y: (mainScreen.visibleFrame.height - windowSize.height) / 2 + mainScreen.visibleFrame.origin.y
        )

        let window = NSWindow(
            contentRect: NSRect(origin: windowOrigin, size: windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "menu.selectScreen".localized
        window.level = .floating
        window.isReleasedWhenClosed = false

        let pickerView = ScreenPickerModalView(
            onSelectScreen: { [weak self] screen in
                window.close()
                self?.captureFullscreen(screen: screen)
            },
            onSelectAll: { [weak self] in
                window.close()
                self?.captureAllScreens()
            },
            onCancel: {
                window.close()
            }
        )

        window.contentView = NSHostingView(rootView: pickerView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Capture Completion

    private func completeCapture(image: NSImage, type: CaptureType) {
        NSLog("[ScreenCaptureService] completeCapture started")

        // Convert NSImage to PNG Data ONCE
        // This creates a completely independent byte buffer with no references to the original image
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            NSLog("[ScreenCaptureService] Failed to convert image to PNG data")
            isCapturing = false
            return
        }

        let imageSize = image.size
        NSLog("[ScreenCaptureService] PNG data created, size: %d bytes, image size: %@", pngData.count, NSStringFromSize(imageSize))

        // Create screenshot directly from PNG data - no NSImage intermediaries
        // Use a single shared ID so history and editor refer to the same logical screenshot
        let screenshotId = UUID()
        let capturedAt = Date()

        let screenshot = Screenshot(
            id: screenshotId,
            pngData: pngData,
            imageSize: imageSize,
            capturedAt: capturedAt,
            captureType: type
        )

        NSLog("[ScreenCaptureService] Screenshot created with id: %@", screenshotId.uuidString)

        currentCapture = screenshot

        // Only save to history if enabled in settings
        if SettingsManager.shared.settings.saveHistory {
            recentCaptures.insert(screenshot, at: 0)

            // Keep only last 10 captures in memory for menu bar popover
            if recentCaptures.count > 10 {
                recentCaptures = Array(recentCaptures.prefix(10))
            }

            // Persist to disk in background — don't block the UI
            let screenshotCopy = screenshot
            DispatchQueue.global(qos: .utility).async {
                HistoryStore.shared.saveInBackground(screenshot: screenshotCopy)
            }
        }

        // Auto-paste mode: copy to clipboard, paste into previous app, skip editor
        if autoPasteAfterCapture {
            autoPasteAfterCapture = false
            copyToClipboard(screenshot)
            isCapturing = false
            pasteToFrontApp()
            NSLog("[ScreenCaptureService] completeCapture finished (auto-paste)")
            return
        }

        // Capture for Claude: save to /tmp, paste file path
        if captureForClaudeMode {
            captureForClaudeMode = false
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let filePath = "/tmp/lucida-capture-\(timestamp).png"
            try? pngData.write(to: URL(fileURLWithPath: filePath))
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(filePath, forType: .string)
            isCapturing = false
            pasteToFrontApp()
            NSLog("[ScreenCaptureService] completeCapture finished (capture-for-claude: %@)", filePath)
            return
        }

        // Auto copy to clipboard
        if SettingsManager.shared.settings.autoCopyToClipboard {
            copyToClipboard(screenshot)
        }

        // Open the annotation editor
        // Pass the PNG data and metadata directly to avoid any reference issues
        openEditorDirectly(
            pngData: pngData,
            imageSize: imageSize,
            screenshotId: screenshotId,
            capturedAt: capturedAt,
            captureType: type
        )

        isCapturing = false
        NSLog("[ScreenCaptureService] completeCapture finished")
    }

    /// Opens the annotation editor directly using PNG data (avoids all reference issues)
    private func openEditorDirectly(
        pngData: Data,
        imageSize: CGSize,
        screenshotId: UUID,
        capturedAt: Date,
        captureType: CaptureType
    ) {
        NSLog("[ScreenCaptureService] openEditorDirectly called with screenshot id: %@", screenshotId.uuidString)

        // Create a fresh Screenshot from the PNG data for the editor
        // This is completely independent - just bytes in memory
        let editorScreenshot = Screenshot(
            id: screenshotId,
            pngData: pngData,
            imageSize: imageSize,
            capturedAt: capturedAt,
            captureType: captureType
        )

        NSLog("[ScreenCaptureService] About to call showEditor")
        AnnotationEditorWindowController.shared.showEditor(for: editorScreenshot) { updatedScreenshot in
            NSLog("[ScreenCaptureService] Save callback invoked")
            Task { @MainActor in
                ScreenCaptureService.shared.saveToFile(updatedScreenshot)
            }
        }
        NSLog("[ScreenCaptureService] showEditor returned")
    }

    // MARK: - Auto-Paste

    /// Re-activate the previous app and simulate Cmd+V to paste the clipboard
    private func pasteToFrontApp() {
        let settings = SettingsManager.shared.settings

        // If "Always paste to iTerm2" is enabled, use AppleScript injection
        // Works from ANY app — no focus switch needed, no Cmd+V
        if settings.alwaysPasteToiTerm {
            pasteToiTermViaScript()
            return
        }

        guard let targetApp = previousApp else {
            NSLog("[Lucida] pasteToFrontApp: no previousApp saved")
            return
        }

        NSLog("[Lucida] pasteToFrontApp: activating %@ (pid %d)", targetApp.localizedName ?? "unknown", targetApp.processIdentifier)

        // Check if target is a terminal — use AppleScript for iTerm2, Cmd+V for others
        if targetApp.bundleIdentifier == "com.googlecode.iterm2" {
            pasteToiTermViaScript()
            return
        }

        // Force activate the target app
        targetApp.activate(options: .activateIgnoringOtherApps)

        // Delay for app to regain focus
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            let source = CGEventSource(stateID: .combinedSessionState)

            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) // 9 = V
            keyDown?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)

            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            keyUp?.flags = .maskCommand
            keyUp?.post(tap: .cghidEventTap)

            NSLog("[Lucida] pasteToFrontApp: Cmd+V posted to %@", targetApp.localizedName ?? "unknown")
        }
    }

    /// Paste clipboard text directly into iTerm2 via AppleScript.
    /// Works from ANY app — no focus switch, no Cmd+V, no timing issues.
    private func pasteToiTermViaScript() {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            NSLog("[Lucida] pasteToiTermViaScript: no text on clipboard")
            return
        }

        // Escape text for AppleScript string (backslashes and quotes)
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = """
        tell application "iTerm2"
            tell current session of current window
                write text "\(escaped)" without newline
            end tell
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let appleScript = NSAppleScript(source: script) {
                appleScript.executeAndReturnError(&error)
                if let error = error {
                    NSLog("[Lucida] pasteToiTermViaScript error: %@", error)
                    // Fallback to Cmd+V
                    DispatchQueue.main.async { [weak self] in
                        self?.previousApp?.activate(options: .activateIgnoringOtherApps)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            let source = CGEventSource(stateID: .combinedSessionState)
                            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
                            keyDown?.flags = .maskCommand
                            keyDown?.post(tap: .cghidEventTap)
                            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
                            keyUp?.flags = .maskCommand
                            keyUp?.post(tap: .cghidEventTap)
                        }
                    }
                } else {
                    NSLog("[Lucida] pasteToiTermViaScript: text injected into iTerm2")
                }
            }
        }
    }

    // MARK: - Helpers

    private func closeCaptureWindows() {
        for window in captureWindows {
            window.close()
        }
        captureWindows.removeAll()
    }

    private func cancelCapture() {
        closeCaptureWindows()
        frozenScreenImages.removeAll()
        resetCaptureFlags()
        isCapturing = false
    }

    private func getDefaultSaveURL() -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "Lucida_\(dateFormatter.string(from: Date())).png"

        let saveLocation = SettingsManager.shared.settings.saveLocation
        return URL(fileURLWithPath: saveLocation).appendingPathComponent(filename)
    }
}

// MARK: - NSHostingView Helper
import SwiftUI

// Removed problematic NSHostingView extension that caused infinite recursion

// MARK: - OCR Result View
struct OCRResultView: View {
    let ocrResult: OCRResult
    let onDismiss: () -> Void

    @State private var copied = false
    @State private var showRaw = false

    private var displayText: String {
        showRaw ? ocrResult.rawText : ocrResult.formattedText
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header with type indicator
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 16))
                Text(L10n.OCR.textCopied)
                    .font(.system(size: 13, weight: .medium))

                Spacer()

                // Detected type badge
                HStack(spacing: 4) {
                    Image(systemName: ocrResult.detectedType.icon)
                        .font(.system(size: 10))
                    Text(ocrResult.detectedType.rawValue)
                        .font(.system(size: 11, weight: .medium))
                    if let lang = ocrResult.detectedLanguage {
                        Text("(\(lang))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.cyan)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.cyan.opacity(0.12))
                )
            }

            // Text preview
            ScrollView {
                Text(displayText)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.05))
            )

            // Line count
            HStack {
                Text("\(ocrResult.lineCount) lines")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                // Toggle raw/formatted
                if ocrResult.rawText != ocrResult.formattedText {
                    Button(action: { showRaw.toggle() }) {
                        HStack(spacing: 4) {
                            Image(systemName: showRaw ? "doc.richtext" : "doc.plaintext")
                            Text(showRaw ? "Formatted" : "Raw")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                Button(action: {
                    OCRService.shared.copyToClipboard(displayText)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                        Text(copied ? "Copied" : "Copy")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))
                )

                Spacer()

                Button(L10n.ScreenSelection.close) {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 460, height: 340)
    }
}

// MARK: - Timed Capture Modal View
struct TimedCaptureModalView: View {
    let onSelect: (Int) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(L10n.Timer.selectDelay)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                TimerOptionButton(seconds: 3, onSelect: onSelect)
                TimerOptionButton(seconds: 5, onSelect: onSelect)
                TimerOptionButton(seconds: 10, onSelect: onSelect)
            }

            Button(L10n.Timer.cancel) {
                onCancel()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.system(size: 12))
        }
        .padding(24)
        .frame(width: 280, height: 180)
    }
}

struct TimerOptionButton: View {
    let seconds: Int
    let onSelect: (Int) -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: { onSelect(seconds) }) {
            VStack(spacing: 6) {
                Text("\(seconds)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(isHovered ? .white : .primary)

                Text(L10n.Timer.seconds)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? .white.opacity(0.8) : .secondary)
            }
            .frame(width: 70, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered ? Color.orange : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Timed Capture Countdown View
struct TimedCaptureCountdownView: View {
    let seconds: Int
    let onComplete: () -> Void

    @State private var countdown: Int

    init(seconds: Int, onComplete: @escaping () -> Void) {
        self.seconds = seconds
        self.onComplete = onComplete
        self._countdown = State(initialValue: seconds)
    }

    var body: some View {
        ZStack {
            // Background
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: 100, height: 100)

            // Progress ring
            Circle()
                .stroke(Color.white.opacity(0.2), lineWidth: 6)
                .frame(width: 90, height: 90)

            Circle()
                .trim(from: 0, to: CGFloat(countdown) / CGFloat(seconds))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 90, height: 90)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: countdown)

            // Countdown number
            Text("\(countdown)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: 120, height: 120)
        .onAppear {
            startCountdown()
        }
    }

    private func startCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdown > 1 {
                countdown -= 1
            } else {
                timer.invalidate()
                onComplete()
            }
        }
    }
}

// MARK: - Screen Picker Modal View

struct ScreenPickerModalView: View {
    let onSelectScreen: (NSScreen) -> Void
    let onSelectAll: () -> Void
    let onCancel: () -> Void

    @State private var hoveredIndex: Int? = nil
    @State private var allHovered = false

    private var screens: [NSScreen] { NSScreen.screens }

    var body: some View {
        VStack(spacing: 12) {
            Text("menu.selectScreen".localized)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            VStack(spacing: 6) {
                ForEach(Array(screens.enumerated()), id: \.offset) { index, screen in
                    ScreenOptionButton(
                        label: screenLabel(index: index, screen: screen),
                        detail: screenDetail(screen: screen),
                        isMain: screen == NSScreen.main,
                        isHovered: hoveredIndex == index
                    ) {
                        onSelectScreen(screen)
                    }
                    .onHover { h in
                        withAnimation(.easeInOut(duration: 0.12)) { hoveredIndex = h ? index : nil }
                    }
                }

                // All Screens option
                ScreenOptionButton(
                    label: "menu.allScreens".localized,
                    detail: allScreensDetail(),
                    isMain: false,
                    isHovered: allHovered
                ) {
                    onSelectAll()
                }
                .onHover { h in
                    withAnimation(.easeInOut(duration: 0.12)) { allHovered = h }
                }
            }

            Button(L10n.Timer.cancel) {
                onCancel()
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .font(.system(size: 12))
        }
        .padding(20)
    }

    private func screenLabel(index: Int, screen: NSScreen) -> String {
        let name = screen.localizedName
        if screen == NSScreen.main {
            return "\(name) (" + "menu.mainScreen".localized + ")"
        }
        return name
    }

    private func screenDetail(screen: NSScreen) -> String {
        let w = Int(screen.frame.width)
        let h = Int(screen.frame.height)
        let scale = Int(screen.backingScaleFactor)
        if scale > 1 {
            return "\(w)x\(h) @\(scale)x"
        }
        return "\(w)x\(h)"
    }

    private func allScreensDetail() -> String {
        let union = screens.reduce(CGRect.null) { $0.union($1.frame) }
        return "\(Int(union.width))x\(Int(union.height))"
    }
}

struct ScreenOptionButton: View {
    let label: String
    let detail: String
    let isMain: Bool
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "display")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isHovered ? .white : .green)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(isHovered ? .white : .primary)
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundColor(isHovered ? .white.opacity(0.7) : .secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.green : Color.primary.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Capture Window (handles ESC key)
class CaptureWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            onEscape?()
            // Don't call super - consume the event completely
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        // Handle ESC/Cmd+. - don't propagate to prevent app termination
        onEscape?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // ESC key
            onEscape?()
            return true // Event handled, don't propagate
        }
        return super.performKeyEquivalent(with: event)
    }
}
