import Foundation

// MARK: - Localization Helper
extension String {
    /// Returns a localized version of the string
    var localized: String {
        NSLocalizedString(self, comment: "")
    }

    /// Returns a localized version of the string with format arguments
    func localized(_ args: CVarArg...) -> String {
        String(format: NSLocalizedString(self, comment: ""), arguments: args)
    }
}

// MARK: - Localization Keys
enum L10n {
    // MARK: - App
    enum App {
        static let failedToOpenProject = "app.failedToOpenProject".localized
    }

    // MARK: - Menu Bar
    enum Menu {
        static let capture = "menu.capture".localized
        static let area = "menu.area".localized
        static let window = "menu.window".localized
        static let fullscreen = "menu.fullscreen".localized
        static let scrolling = "menu.scrolling".localized
        static let scrollingNew = "menu.scrolling.new".localized
        static let tools = "menu.tools".localized
        static let ruler = "menu.ruler".localized
        static let colorPicker = "menu.colorPicker".localized
        static let ocr = "menu.ocr".localized
        static let recentCaptures = "menu.recentCaptures".localized
        static let noRecentCaptures = "menu.noRecentCaptures".localized
        static let showAll = "menu.showAll".localized
        static let settings = "menu.settings".localized
        static let quit = "menu.quit".localized
        static let history = "menu.history".localized
        static let paste = "menu.paste".localized
        static let ocrPaste = "menu.ocrPaste".localized
        static let captureError = "menu.captureError".localized
        static let captureForClaude = "menu.captureForClaude".localized
        static let captureCode = "menu.captureCode".localized
        static let smartCapture = "menu.smartCapture".localized
        static let selectScreen = "menu.selectScreen".localized
        static let allScreens = "menu.allScreens".localized
        static let mainScreen = "menu.mainScreen".localized
        static let back = "menu.back".localized
        static let autoCopyToggle = "menu.autoCopy".localized
        static let hideDesktop = "menu.hideDesktop".localized
    }

    // MARK: - Capture Types
    enum Capture {
        static let area = "capture.area".localized
        static let window = "capture.window".localized
        static let fullscreen = "capture.fullscreen".localized
        static let scrolling = "capture.scrolling".localized
    }

    // MARK: - Quick Overlay
    enum Overlay {
        static let copy = "overlay.copy".localized
        static let save = "overlay.save".localized
        static let annotate = "overlay.annotate".localized
        static let pin = "overlay.pin".localized
        static let close = "overlay.close".localized
        static let justNow = "overlay.justNow".localized
        static let copied = "overlay.copied".localized
        static let backdrop = "overlay.backdrop".localized
        enum Backdrop {
            static let none = "overlay.backdrop.none".localized
            static let white = "overlay.backdrop.white".localized
            static let dark = "overlay.backdrop.dark".localized
            static let gradient = "overlay.backdrop.gradient".localized
        }
    }

    // MARK: - Annotation Editor
    enum Annotation {
        static let title = "annotation.title".localized
        static let arrow = "annotation.arrow".localized
        static let rectangle = "annotation.rectangle".localized
        static let ellipse = "annotation.ellipse".localized
        static let line = "annotation.line".localized
        static let text = "annotation.text".localized
        static let blur = "annotation.blur".localized
        static let highlight = "annotation.highlight".localized
        static let freehand = "annotation.freehand".localized
        static let undo = "annotation.undo".localized
        static let redo = "annotation.redo".localized
        static let clear = "annotation.clear".localized
        static let cancel = "annotation.cancel".localized
        static let addText = "annotation.addText".localized
        static let addTextTitle = "annotation.addTextTitle".localized
        static let textPlaceholder = "annotation.textPlaceholder".localized
        static let copiedToClipboard = "annotation.copiedToClipboard".localized
        static let back = "annotation.back".localized
        static let front = "annotation.front".localized
        static let ocr = "annotation.ocr".localized
        static let describe = "annotation.describe".localized
        static let saveProject = "annotation.saveProject".localized
        static let delete = "annotation.delete".localized
        static let duplicate = "annotation.duplicate".localized
        static let bringToFront = "annotation.bringToFront".localized
        static let sendToBack = "annotation.sendToBack".localized
        static let backdrop = "annotation.backdrop".localized
        enum BackdropLabels {
            static let type = "annotation.backdrop.type".localized
            static let shadow = "annotation.backdrop.shadow".localized
            static let blurAmount = "annotation.backdrop.blur".localized
            static let offset = "annotation.backdrop.offset".localized
            static let opacity = "annotation.backdrop.opacity".localized
            static let borderRadius = "annotation.backdrop.borderRadius".localized
            static let inner = "annotation.backdrop.inner".localized
            static let outer = "annotation.backdrop.outer".localized
            static let solidColors = "annotation.backdrop.solidColors".localized
            static let direction = "annotation.backdrop.direction".localized
            static let gradients = "annotation.backdrop.gradients".localized
        }
        static func annotations(_ count: Int) -> String {
            count == 1 ? "annotation.annotations".localized(count) : "annotation.annotationsPlural".localized(count)
        }
    }

    // MARK: - Settings
    enum Settings {
        static let title = "settings.title".localized
        static let general = "settings.general".localized
        static let hotkeys = "settings.hotkeys".localized
        static let ai = "settings.ai".localized
        static let about = "settings.about".localized

        // General
        static let appearance = "settings.appearance".localized
        static let appearanceDescription = "settings.appearance.description".localized
        static let appearanceSystem = "settings.appearance.system".localized
        static let appearanceLight = "settings.appearance.light".localized
        static let appearanceDark = "settings.appearance.dark".localized
        static let capture = "settings.capture".localized
        static let autoCopy = "settings.autoCopy".localized
        static let autoCopyDescription = "settings.autoCopy.description".localized
        static let hideDesktopIcons = "settings.hideDesktopIcons".localized
        static let hideDesktopIconsDescription = "settings.hideDesktopIcons.description".localized
        static let freezeScreen = "settings.freezeScreen".localized
        static let freezeScreenDescription = "settings.freezeScreen.description".localized
        static let storage = "settings.storage".localized
        static let saveLocation = "settings.saveLocation".localized
        static let choose = "settings.choose".localized

        // Hotkeys
        static let shortcuts = "settings.shortcuts".localized
        static let areaCapture = "settings.areaCapture".localized
        static let windowCapture = "settings.windowCapture".localized
        static let fullscreenCapture = "settings.fullscreenCapture".localized
        static let autoPasteCapture = "settings.autoPasteCapture".localized
        static let ocrPasteCapture = "settings.ocrPasteCapture".localized
        static let allScreensCapture = "settings.allScreensCapture".localized
        static let scrollingCapture = "settings.scrollingCapture".localized
        static let ocrCapture = "settings.ocrCapture".localized
        static let colorPickerHotkey = "settings.colorPickerHotkey".localized
        static let pixelRuler = "settings.pixelRuler".localized
        static let timedCapture = "settings.timedCapture".localized
        static let activeWindowCapture = "settings.activeWindowCapture".localized
        static let unifiedCapture = "settings.unifiedCapture".localized
        static let captureError = "settings.captureError".localized
        static let captureForClaude = "settings.captureForClaude".localized
        static let captureCode = "settings.captureCode".localized
        static let recaptureLastArea = "settings.recaptureLastArea".localized
        static let smartCapture = "settings.smartCapture".localized
        static let captureWindowShadow = "settings.captureWindowShadow".localized
        static let recording = "settings.recording".localized
        static let permissions = "settings.permissions".localized
        static let permissionsDescription = "settings.permissions.description".localized
        static let openSettings = "settings.openSettings".localized

        // Startup
        static let startup = "settings.startup".localized
        static let launchAtLogin = "settings.launchAtLogin".localized
        static let launchAtLoginDescription = "settings.launchAtLogin.description".localized
        static let showInDock = "settings.showInDock".localized
        static let showInDockDescription = "settings.showInDock.description".localized

        // Privacy
        static let privacy = "settings.privacy".localized
        static let saveHistory = "settings.saveHistory".localized
        static let saveHistoryDescription = "settings.saveHistory.description".localized

        // OCR
        static let ocrSection = "settings.ocrSection".localized
        static let ocrOutputFormat = "settings.ocrOutputFormat".localized
        static let ocrFormatAuto = "settings.ocrFormat.auto".localized
        static let ocrFormatMarkdown = "settings.ocrFormat.markdown".localized
        static let ocrFormatPlain = "settings.ocrFormat.plain".localized

        // Image format
        static let imageFormat = "settings.imageFormat".localized
        static let imageFormatAuto = "settings.imageFormat.auto".localized
        static let jpgQuality = "settings.jpgQuality".localized
        static let jpgQualitySmaller = "settings.jpgQuality.smaller".localized
        static let jpgQualityBetter = "settings.jpgQuality.better".localized

        // AI
        static let llmConfig = "settings.llmConfig".localized
        static let provider = "settings.provider".localized
        static let apiKey = "settings.apiKey".localized
        static let apiKeyPlaceholder = "settings.apiKeyPlaceholder".localized
        static let apiKeySecure = "settings.apiKeySecure".localized
        static let aiFeatures = "settings.aiFeatures".localized
        static let smartDescriptions = "settings.smartDescriptions".localized
        static let smartDescriptionsDescription = "settings.smartDescriptions.description".localized
        static let ocrExtraction = "settings.ocrExtraction".localized
        static let ocrExtractionDescription = "settings.ocrExtraction.description".localized
        static let contentSuggestions = "settings.contentSuggestions".localized
        static let contentSuggestionsDescription = "settings.contentSuggestions.description".localized
        static let aiOnDevice = "settings.ai.onDevice".localized
        static let aiOnDeviceDescription = "settings.ai.onDevice.description".localized

        // LLM Cleanup
        static let llmCleanup = "settings.llmCleanup".localized
        static let llmCleanupDescription = "settings.llmCleanup.description".localized
        static let llmCleanupOllamaRunning = "settings.llmCleanup.ollamaRunning".localized
        static let llmCleanupOllamaOffline = "settings.llmCleanup.ollamaOffline".localized
        static let llmCleanupModel = "settings.llmCleanup.model".localized
        static let llmCleanupModelName = "settings.llmCleanup.modelName".localized

        // About
        static func version(_ v: String) -> String { "settings.version".localized(v) }
        static let tagline = "settings.tagline".localized
        static let openSource = "settings.openSource".localized
        static let viewOnGitHub = "settings.viewOnGitHub".localized
        static let madeWith = "settings.madeWith".localized
        static let madeBy = "settings.madeBy".localized
    }

    // MARK: - Capture History
    enum History {
        static let title = "history.title".localized
        static let all = "history.all".localized
        static let areas = "history.areas".localized
        static let windows = "history.windows".localized
        static let fullscreens = "history.fullscreens".localized
        static let newest = "history.newest".localized
        static let oldest = "history.oldest".localized
        static let noCaptures = "history.noCaptures".localized
        static let noCapturesDescription = "history.noCaptures.description".localized
        static let startCapturing = "history.startCapturing".localized
        static let delete = "history.delete".localized
        static let showInFinder = "history.showInFinder".localized
    }

    // MARK: - Permissions
    enum Permissions {
        static let title = "permissions.title".localized
        static let description = "permissions.description".localized
        static let screenRecording = "permissions.screenRecording".localized
        static let screenRecordingDescription = "permissions.screenRecording.description".localized
        static let accessibility = "permissions.accessibility".localized
        static let accessibilityDescription = "permissions.accessibility.description".localized
        static let granted = "permissions.granted".localized
        static let continueButton = "permissions.continue".localized
        static let showInFinder = "permissions.showInFinder".localized
        static let restart = "permissions.restart".localized
        static let later = "permissions.later".localized
        static let instructions = "permissions.instructions".localized
        static let step1 = "permissions.step1".localized
        static let step2 = "permissions.step2".localized
        static let step3 = "permissions.step3".localized
    }

    // MARK: - Window Selection
    enum WindowSelection {
        static let title = "windowSelection.title".localized
        static let scrollingTitle = "windowSelection.scrollingTitle".localized
        static let cancel = "windowSelection.cancel".localized
        static let escToCancel = "windowSelection.escToCancel".localized
    }

    // MARK: - Context Menu
    enum ContextMenu {
        static let appearance = "contextMenu.appearance".localized
        static let copy = "contextMenu.copy".localized
        static let save = "contextMenu.save".localized
        static let annotate = "contextMenu.annotate".localized
        static let pin = "contextMenu.pin".localized
        static let delete = "contextMenu.delete".localized
        static let dark = "contextMenu.dark".localized
        static let light = "contextMenu.light".localized
        static let system = "contextMenu.system".localized
        static let settings = "contextMenu.settings".localized
        static let quit = "contextMenu.quit".localized
    }

    // MARK: - Area Selection
    enum AreaSelection {
        static let instruction = "areaSelection.instruction".localized
        static let unifiedInstruction = "areaSelection.unifiedInstruction".localized
    }

    // MARK: - Floating Window
    enum Floating {
        static let clickThrough = "floating.clickThrough".localized
        static let copied = "floating.copied".localized
    }

    // MARK: - Color Picker
    enum ColorPicker {
        static let pickedColor = "colorPicker.pickedColor".localized
    }

    // MARK: - OCR
    enum OCR {
        static let failed = "ocr.failed".localized
        static let textCopied = "ocr.textCopied".localized
    }

    // MARK: - Timer
    enum Timer {
        static let selectDelay = "timer.selectDelay".localized
        static let seconds = "timer.seconds".localized
        static let cancel = "timer.cancel".localized
    }

    // MARK: - Screen Selection
    enum ScreenSelection {
        static let cancel = "screenSelection.cancel".localized
        static let close = "screenSelection.close".localized
    }

    // MARK: - Welcome HUD
    enum Welcome {
        static let ready = "welcome.ready".localized
        static let description = "welcome.description".localized
        static let area = "welcome.area".localized
        static let autoPaste = "welcome.autoPaste".localized
        static let ocrPaste = "welcome.ocrPaste".localized
        static let forClaude = "welcome.forClaude".localized
    }

    // MARK: - Smart Capture
    enum SmartCapture {
        static let paste = "smartCapture.paste".localized
        static let placeholder = "smartCapture.placeholder".localized
    }

    // MARK: - Onboarding
    enum Onboarding {
        static let setup = "onboarding.setup".localized
        static let screenRecording = "onboarding.screenRecording".localized
        static let screenRecordingDescription = "onboarding.screenRecording.description".localized
        static let openSystemSettings = "onboarding.openSystemSettings".localized
        static let screenRecordingHint = "onboarding.screenRecording.hint".localized
        static let screenRecordingRestart = "onboarding.screenRecording.restart".localized
        static let accessibility = "onboarding.accessibility".localized
        static let accessibilityDescription = "onboarding.accessibility.description".localized
        static let grantAccessibility = "onboarding.grantAccessibility".localized
        static let openSettingsManually = "onboarding.openSettingsManually".localized
        static let accessibilityEnabled = "onboarding.accessibilityEnabled".localized
        static let allSet = "onboarding.allSet".localized
        static let allSetDescription = "onboarding.allSet.description".localized
        static let area = "onboarding.area".localized
        static let window = "onboarding.window".localized
        static let fullscreen = "onboarding.fullscreen".localized
    }
}
