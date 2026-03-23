import Foundation
import AppKit
import CoreGraphics

/// Represents a captured screenshot with metadata.
/// IMPORTANT: This is a STRUCT that stores image as PNG Data.
/// Being a value type, it's copied on assignment, avoiding all reference issues.
struct Screenshot: Identifiable {
    let id: UUID
    /// Store PNG data - completely independent, value-type storage
    let pngData: Data
    /// Cached size
    let imageSize: CGSize
    let capturedAt: Date
    let captureType: CaptureType
    var annotations: [Annotation]
    var extractedText: String?
    var aiDescription: String?

    /// Returns a NEW NSImage each time from the stored PNG data.
    var image: NSImage {
        guard let img = NSImage(data: pngData) else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }
        return img
    }

    /// Initialize from NSImage - converts to PNG data immediately
    init(
        id: UUID = UUID(),
        image: NSImage,
        capturedAt: Date = Date(),
        captureType: CaptureType,
        annotations: [Annotation] = [],
        extractedText: String? = nil,
        aiDescription: String? = nil
    ) {
        self.id = id
        self.capturedAt = capturedAt
        self.captureType = captureType
        self.annotations = annotations
        self.extractedText = extractedText
        self.aiDescription = aiDescription
        self.imageSize = image.size

        // Convert to PNG data immediately
        if let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let png = bitmap.representation(using: .png, properties: [:]) {
            self.pngData = png
        } else if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            self.pngData = bitmapRep.representation(using: .png, properties: [:]) ?? Data()
        } else {
            self.pngData = Data()
        }
    }

    /// Initialize directly from PNG data
    init(
        id: UUID = UUID(),
        pngData: Data,
        imageSize: CGSize,
        capturedAt: Date = Date(),
        captureType: CaptureType,
        annotations: [Annotation] = [],
        extractedText: String? = nil,
        aiDescription: String? = nil
    ) {
        self.id = id
        self.pngData = pngData
        self.imageSize = imageSize
        self.capturedAt = capturedAt
        self.captureType = captureType
        self.annotations = annotations
        self.extractedText = extractedText
        self.aiDescription = aiDescription
    }
}

/// Type of screen capture
enum CaptureType: String, Codable, CaseIterable {
    case area = "Area"
    case window = "Window"
    case fullscreen = "Fullscreen"

    var icon: String {
        switch self {
        case .area: return "rectangle.dashed"
        case .window: return "macwindow"
        case .fullscreen: return "rectangle.inset.filled"
        }
    }

    var shortcut: String {
        switch self {
        case .area: return "⌘⇧4"
        case .window: return "⌘⇧5"
        case .fullscreen: return "⌘⇧3"
        }
    }
}

/// Callout arrow direction
enum CalloutArrowDirection: String, Codable, CaseIterable {
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
    case topLeft = "Top Left"
    case topRight = "Top Right"
}

/// Annotation on a screenshot
struct Annotation: Identifiable, Codable {
    let id: UUID
    var type: AnnotationType
    var startPoint: CGPoint
    var endPoint: CGPoint
    var colorHex: String
    var strokeWidth: CGFloat
    var text: String?
    var points: [CGPoint]  // For freehand drawing
    var fontSize: CGFloat
    var fontWeight: String
    var fontName: String
    var calloutArrowDirection: CalloutArrowDirection  // For callout annotations
    var stepNumber: Int?  // For step counter annotations
    var stepCounterFormat: StepCounterFormat  // Format for step counter
    var redactionStyle: RedactionStyle  // For blur/pixelate redaction
    var redactionIntensity: CGFloat  // 0.0 to 1.0 for blur/pixelate intensity
    var zIndex: Int  // For layer ordering (higher = on top)

    // Computed property for NSColor (not encoded)
    var color: NSColor {
        get { NSColor(hex: colorHex) ?? .systemRed }
        set { colorHex = newValue.hexString }
    }

    init(
        id: UUID = UUID(),
        type: AnnotationType,
        startPoint: CGPoint,
        endPoint: CGPoint = .zero,
        color: NSColor = .systemRed,
        strokeWidth: CGFloat = 3.0,
        text: String? = nil,
        points: [CGPoint] = [],
        fontSize: CGFloat = 16,
        fontWeight: String = "medium",
        fontName: String = "System",
        calloutArrowDirection: CalloutArrowDirection = .bottomLeft,
        stepNumber: Int? = nil,
        stepCounterFormat: StepCounterFormat = .numeric,
        redactionStyle: RedactionStyle = .blur,
        redactionIntensity: CGFloat = 0.7,
        zIndex: Int = 0
    ) {
        self.id = id
        self.type = type
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.colorHex = color.hexString
        self.strokeWidth = strokeWidth
        self.text = text
        self.points = points
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.fontName = fontName
        self.calloutArrowDirection = calloutArrowDirection
        self.stepNumber = stepNumber
        self.stepCounterFormat = stepCounterFormat
        self.redactionStyle = redactionStyle
        self.redactionIntensity = redactionIntensity
        self.zIndex = zIndex
    }

    enum CodingKeys: String, CodingKey {
        case id, type, startPoint, endPoint, colorHex, strokeWidth, text, points, fontSize, fontWeight, fontName, calloutArrowDirection, stepNumber, stepCounterFormat, redactionStyle, redactionIntensity, zIndex
    }

    // Custom decoder to handle missing keys from older .lucida files
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(AnnotationType.self, forKey: .type)
        startPoint = try container.decode(CGPoint.self, forKey: .startPoint)
        endPoint = try container.decode(CGPoint.self, forKey: .endPoint)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        strokeWidth = try container.decode(CGFloat.self, forKey: .strokeWidth)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        points = try container.decode([CGPoint].self, forKey: .points)
        fontSize = try container.decode(CGFloat.self, forKey: .fontSize)
        fontWeight = try container.decode(String.self, forKey: .fontWeight)
        fontName = try container.decode(String.self, forKey: .fontName)
        calloutArrowDirection = try container.decodeIfPresent(CalloutArrowDirection.self, forKey: .calloutArrowDirection) ?? .bottomLeft
        // New fields with defaults for backward compatibility
        stepNumber = try container.decodeIfPresent(Int.self, forKey: .stepNumber)
        stepCounterFormat = try container.decodeIfPresent(StepCounterFormat.self, forKey: .stepCounterFormat) ?? .numeric
        redactionStyle = try container.decodeIfPresent(RedactionStyle.self, forKey: .redactionStyle) ?? .blur
        redactionIntensity = try container.decodeIfPresent(CGFloat.self, forKey: .redactionIntensity) ?? 0.7
        zIndex = try container.decodeIfPresent(Int.self, forKey: .zIndex) ?? 0
    }
}

/// Step counter format for numbered annotations
enum StepCounterFormat: String, Codable, CaseIterable {
    case numeric = "1, 2, 3"
    case alphabeticUpper = "A, B, C"
    case alphabeticLower = "a, b, c"
    case romanUpper = "I, II, III"
    case romanLower = "i, ii, iii"

    func format(_ number: Int) -> String {
        switch self {
        case .numeric:
            return "\(number)"
        case .alphabeticUpper:
            return number <= 26 ? String(Character(UnicodeScalar(64 + number)!)) : "\(number)"
        case .alphabeticLower:
            return number <= 26 ? String(Character(UnicodeScalar(96 + number)!)) : "\(number)"
        case .romanUpper:
            return toRoman(number).uppercased()
        case .romanLower:
            return toRoman(number).lowercased()
        }
    }

    private func toRoman(_ number: Int) -> String {
        let romanValues: [(Int, String)] = [
            (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"),
            (100, "C"), (90, "XC"), (50, "L"), (40, "XL"),
            (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")
        ]
        var result = ""
        var remaining = number
        for (value, numeral) in romanValues {
            while remaining >= value {
                result += numeral
                remaining -= value
            }
        }
        return result
    }
}

/// Redaction style for privacy tools
enum RedactionStyle: String, Codable, CaseIterable {
    case blur = "Blur"
    case pixelate = "Pixelate"
    case solidBlack = "Black"
    case solidWhite = "White"

    var icon: String {
        switch self {
        case .blur: return "drop.halffull"
        case .pixelate: return "square.grid.3x3"
        case .solidBlack: return "rectangle.fill"
        case .solidWhite: return "rectangle"
        }
    }
}

/// Types of annotations available
enum AnnotationType: String, Codable, CaseIterable {
    case select = "Select"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case ellipse = "Ellipse"
    case line = "Line"
    case text = "Text"
    case blur = "Blur"
    case pixelate = "Pixelate"
    case highlight = "Highlight"
    case freehand = "Freehand"
    case erase = "Erase"
    case stepCounter = "Step"

    var icon: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .line: return "line.diagonal"
        case .text: return "textformat"
        case .blur: return "drop.halffull"
        case .pixelate: return "square.grid.3x3"
        case .highlight: return "highlighter"
        case .freehand: return "pencil.tip"
        case .erase: return "eraser"
        case .stepCounter: return "number.circle"
        }
    }
}

/// App appearance mode
enum AppearanceMode: String, Codable, CaseIterable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.fill"
        }
    }
}

/// Image format for saving
enum ImageFormat: String, Codable, CaseIterable {
    case png = "PNG"
    case jpg = "JPG"
    case webp = "WebP"
    case pdf = "PDF"
    case auto = "Auto"

    var icon: String {
        switch self {
        case .png: return "doc.richtext"
        case .jpg: return "photo"
        case .webp: return "doc.zipper"
        case .pdf: return "doc.fill"
        case .auto: return "wand.and.stars"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpg: return "jpg"
        case .webp: return "webp"
        case .pdf: return "pdf"
        case .auto: return "png" // Default for auto
        }
    }
}

/// Text annotation settings
struct TextAnnotationSettings: Codable, Equatable {
    var fontName: String
    var fontSize: CGFloat
    var fontWeight: String
    var colorHex: String

    static var `default`: TextAnnotationSettings {
        TextAnnotationSettings(
            fontName: "System",
            fontSize: 16,
            fontWeight: "medium",
            colorHex: "#FF0000"
        )
    }

    var nsFont: NSFont {
        let weight: NSFont.Weight
        switch fontWeight {
        case "ultralight": weight = .ultraLight
        case "thin": weight = .thin
        case "light": weight = .light
        case "regular": weight = .regular
        case "medium": weight = .medium
        case "semibold": weight = .semibold
        case "bold": weight = .bold
        case "heavy": weight = .heavy
        case "black": weight = .black
        default: weight = .medium
        }

        if fontName == "System" {
            return NSFont.systemFont(ofSize: fontSize, weight: weight)
        } else {
            return NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: weight)
        }
    }
}

/// App settings model
struct AppSettings: Codable {
    var anthropicApiKey: String
    var openaiApiKey: String
    var llmProvider: LLMProvider

    // Computed property for current provider's API key (not encoded)
    var llmApiKey: String {
        get {
            switch llmProvider {
            case .local: return ""
            case .anthropic: return anthropicApiKey
            case .openai: return openaiApiKey
            }
        }
        set {
            switch llmProvider {
            case .local: break
            case .anthropic: anthropicApiKey = newValue
            case .openai: openaiApiKey = newValue
            }
        }
    }
    var saveLocation: String

    // Custom CodingKeys - exclude llmApiKey as it's computed
    enum CodingKeys: String, CodingKey {
        case anthropicApiKey, openaiApiKey, llmProvider, saveLocation, autoCopyToClipboard
        case hideDesktopIcons
        case hotkeys, appearanceMode, launchAtStartup, imageFormat, jpgQuality, webpQuality
        case defaultAnnotationColor, defaultStrokeWidth, defaultAnnotationTool
        case textAnnotationSettings, filenameTemplate, sequentialNumber
        case autoSaveOnEditorClose, autoCopyOnEditorClose, maxVideoRecordingDuration
        case defaultRedactionStyle, defaultRedactionIntensity, defaultStepCounterFormat
        case showInDock
        case saveHistory, maxHistoryItems
        case freezeScreenBeforeCapture
        case captureWindowShadow
        case quickOverlayAutoDismiss, quickOverlayTimeout
        case ocrOutputFormat, ocrLLMCleanup, ocrCleanupModel
        // Legacy key for backward compatibility
        case llmApiKey
    }

    // Custom decoder for backward compatibility with old settings
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle API keys - check for new format first, fall back to legacy
        if let anthropic = try container.decodeIfPresent(String.self, forKey: .anthropicApiKey) {
            anthropicApiKey = anthropic
            openaiApiKey = try container.decodeIfPresent(String.self, forKey: .openaiApiKey) ?? ""
        } else if let legacyKey = try container.decodeIfPresent(String.self, forKey: .llmApiKey) {
            // Migrate legacy key to the current provider
            let provider = try container.decodeIfPresent(LLMProvider.self, forKey: .llmProvider) ?? .anthropic
            if provider == .anthropic {
                anthropicApiKey = legacyKey
                openaiApiKey = ""
            } else {
                anthropicApiKey = ""
                openaiApiKey = legacyKey
            }
        } else {
            anthropicApiKey = ""
            openaiApiKey = ""
        }

        llmProvider = try container.decodeIfPresent(LLMProvider.self, forKey: .llmProvider) ?? .anthropic
        saveLocation = try container.decode(String.self, forKey: .saveLocation)
        autoCopyToClipboard = try container.decode(Bool.self, forKey: .autoCopyToClipboard)
        hideDesktopIcons = try container.decode(Bool.self, forKey: .hideDesktopIcons)
        hotkeys = try container.decode(HotkeySettings.self, forKey: .hotkeys)
        appearanceMode = try container.decode(AppearanceMode.self, forKey: .appearanceMode)
        launchAtStartup = try container.decode(Bool.self, forKey: .launchAtStartup)
        imageFormat = try container.decodeIfPresent(ImageFormat.self, forKey: .imageFormat) ?? .auto
        jpgQuality = try container.decodeIfPresent(Double.self, forKey: .jpgQuality) ?? 0.8
        webpQuality = try container.decodeIfPresent(Double.self, forKey: .webpQuality) ?? 0.8
        defaultAnnotationColor = try container.decodeIfPresent(String.self, forKey: .defaultAnnotationColor) ?? "red"
        defaultStrokeWidth = try container.decodeIfPresent(Double.self, forKey: .defaultStrokeWidth) ?? 3.0
        defaultAnnotationTool = try container.decodeIfPresent(String.self, forKey: .defaultAnnotationTool) ?? "arrow"
        textAnnotationSettings = try container.decodeIfPresent(TextAnnotationSettings.self, forKey: .textAnnotationSettings) ?? .default
        filenameTemplate = try container.decodeIfPresent(String.self, forKey: .filenameTemplate) ?? "Lucida_{date}_{time}"
        sequentialNumber = try container.decodeIfPresent(Int.self, forKey: .sequentialNumber) ?? 1
        autoSaveOnEditorClose = try container.decodeIfPresent(Bool.self, forKey: .autoSaveOnEditorClose) ?? false
        autoCopyOnEditorClose = try container.decodeIfPresent(Bool.self, forKey: .autoCopyOnEditorClose) ?? true
        maxVideoRecordingDuration = try container.decodeIfPresent(Int.self, forKey: .maxVideoRecordingDuration) ?? 20
        defaultRedactionStyle = try container.decodeIfPresent(RedactionStyle.self, forKey: .defaultRedactionStyle) ?? .blur
        defaultRedactionIntensity = try container.decodeIfPresent(Double.self, forKey: .defaultRedactionIntensity) ?? 0.7
        defaultStepCounterFormat = try container.decodeIfPresent(StepCounterFormat.self, forKey: .defaultStepCounterFormat) ?? .numeric
        showInDock = try container.decodeIfPresent(Bool.self, forKey: .showInDock) ?? false
        saveHistory = try container.decodeIfPresent(Bool.self, forKey: .saveHistory) ?? true
        maxHistoryItems = try container.decodeIfPresent(Int.self, forKey: .maxHistoryItems) ?? 100
        freezeScreenBeforeCapture = try container.decodeIfPresent(Bool.self, forKey: .freezeScreenBeforeCapture) ?? true
        captureWindowShadow = try container.decodeIfPresent(Bool.self, forKey: .captureWindowShadow) ?? true
        quickOverlayAutoDismiss = try container.decodeIfPresent(Bool.self, forKey: .quickOverlayAutoDismiss) ?? true
        quickOverlayTimeout = try container.decodeIfPresent(Double.self, forKey: .quickOverlayTimeout) ?? 5.0
        ocrOutputFormat = try container.decodeIfPresent(OCROutputFormat.self, forKey: .ocrOutputFormat) ?? .auto
        ocrLLMCleanup = try container.decodeIfPresent(Bool.self, forKey: .ocrLLMCleanup) ?? false
        ocrCleanupModel = try container.decodeIfPresent(String.self, forKey: .ocrCleanupModel) ?? "gemma3:4b"
    }

    // Custom encoder - don't encode the computed llmApiKey
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(anthropicApiKey, forKey: .anthropicApiKey)
        try container.encode(openaiApiKey, forKey: .openaiApiKey)
        try container.encode(llmProvider, forKey: .llmProvider)
        try container.encode(saveLocation, forKey: .saveLocation)
        try container.encode(autoCopyToClipboard, forKey: .autoCopyToClipboard)
        try container.encode(hideDesktopIcons, forKey: .hideDesktopIcons)
        try container.encode(hotkeys, forKey: .hotkeys)
        try container.encode(appearanceMode, forKey: .appearanceMode)
        try container.encode(launchAtStartup, forKey: .launchAtStartup)
        try container.encode(imageFormat, forKey: .imageFormat)
        try container.encode(jpgQuality, forKey: .jpgQuality)
        try container.encode(webpQuality, forKey: .webpQuality)
        try container.encode(defaultAnnotationColor, forKey: .defaultAnnotationColor)
        try container.encode(defaultStrokeWidth, forKey: .defaultStrokeWidth)
        try container.encode(defaultAnnotationTool, forKey: .defaultAnnotationTool)
        try container.encode(textAnnotationSettings, forKey: .textAnnotationSettings)
        try container.encode(filenameTemplate, forKey: .filenameTemplate)
        try container.encode(sequentialNumber, forKey: .sequentialNumber)
        try container.encode(autoSaveOnEditorClose, forKey: .autoSaveOnEditorClose)
        try container.encode(autoCopyOnEditorClose, forKey: .autoCopyOnEditorClose)
        try container.encode(maxVideoRecordingDuration, forKey: .maxVideoRecordingDuration)
        try container.encode(defaultRedactionStyle, forKey: .defaultRedactionStyle)
        try container.encode(defaultRedactionIntensity, forKey: .defaultRedactionIntensity)
        try container.encode(defaultStepCounterFormat, forKey: .defaultStepCounterFormat)
        try container.encode(showInDock, forKey: .showInDock)
        try container.encode(saveHistory, forKey: .saveHistory)
        try container.encode(maxHistoryItems, forKey: .maxHistoryItems)
        try container.encode(freezeScreenBeforeCapture, forKey: .freezeScreenBeforeCapture)
        try container.encode(captureWindowShadow, forKey: .captureWindowShadow)
        try container.encode(quickOverlayAutoDismiss, forKey: .quickOverlayAutoDismiss)
        try container.encode(quickOverlayTimeout, forKey: .quickOverlayTimeout)
        try container.encode(ocrOutputFormat, forKey: .ocrOutputFormat)
        try container.encode(ocrLLMCleanup, forKey: .ocrLLMCleanup)
        try container.encode(ocrCleanupModel, forKey: .ocrCleanupModel)
    }
    var autoCopyToClipboard: Bool
    var hideDesktopIcons: Bool
    var hotkeys: HotkeySettings
    var appearanceMode: AppearanceMode
    var launchAtStartup: Bool
    var imageFormat: ImageFormat
    var jpgQuality: Double
    var webpQuality: Double
    var defaultAnnotationColor: String
    var defaultStrokeWidth: Double
    var defaultAnnotationTool: String
    var textAnnotationSettings: TextAnnotationSettings
    var filenameTemplate: String
    var sequentialNumber: Int
    var autoSaveOnEditorClose: Bool
    var autoCopyOnEditorClose: Bool
    var maxVideoRecordingDuration: Int  // seconds (max 20)
    var defaultRedactionStyle: RedactionStyle
    var defaultRedactionIntensity: Double
    var defaultStepCounterFormat: StepCounterFormat
    var showInDock: Bool
    var saveHistory: Bool
    var maxHistoryItems: Int
    var freezeScreenBeforeCapture: Bool
    var captureWindowShadow: Bool
    var quickOverlayAutoDismiss: Bool
    var quickOverlayTimeout: Double
    var ocrOutputFormat: OCROutputFormat
    var ocrLLMCleanup: Bool
    var ocrCleanupModel: String

    // Memberwise init (needed because we have custom Codable)
    init(
        anthropicApiKey: String,
        openaiApiKey: String,
        llmProvider: LLMProvider,
        saveLocation: String,
        autoCopyToClipboard: Bool,
        hideDesktopIcons: Bool,
        hotkeys: HotkeySettings,
        appearanceMode: AppearanceMode,
        launchAtStartup: Bool,
        imageFormat: ImageFormat,
        jpgQuality: Double,
        webpQuality: Double,
        defaultAnnotationColor: String,
        defaultStrokeWidth: Double,
        defaultAnnotationTool: String,
        textAnnotationSettings: TextAnnotationSettings,
        filenameTemplate: String,
        sequentialNumber: Int,
        autoSaveOnEditorClose: Bool,
        autoCopyOnEditorClose: Bool,
        maxVideoRecordingDuration: Int,
        defaultRedactionStyle: RedactionStyle,
        defaultRedactionIntensity: Double,
        defaultStepCounterFormat: StepCounterFormat,
        showInDock: Bool,
        saveHistory: Bool,
        maxHistoryItems: Int,
        freezeScreenBeforeCapture: Bool = true,
        captureWindowShadow: Bool = true,
        quickOverlayAutoDismiss: Bool = true,
        quickOverlayTimeout: Double = 5.0,
        ocrOutputFormat: OCROutputFormat = .auto,
        ocrLLMCleanup: Bool = false,
        ocrCleanupModel: String = "gemma3:4b"
    ) {
        self.anthropicApiKey = anthropicApiKey
        self.openaiApiKey = openaiApiKey
        self.llmProvider = llmProvider
        self.saveLocation = saveLocation
        self.autoCopyToClipboard = autoCopyToClipboard
        self.hideDesktopIcons = hideDesktopIcons
        self.hotkeys = hotkeys
        self.appearanceMode = appearanceMode
        self.launchAtStartup = launchAtStartup
        self.imageFormat = imageFormat
        self.jpgQuality = jpgQuality
        self.webpQuality = webpQuality
        self.defaultAnnotationColor = defaultAnnotationColor
        self.defaultStrokeWidth = defaultStrokeWidth
        self.defaultAnnotationTool = defaultAnnotationTool
        self.textAnnotationSettings = textAnnotationSettings
        self.filenameTemplate = filenameTemplate
        self.sequentialNumber = sequentialNumber
        self.autoSaveOnEditorClose = autoSaveOnEditorClose
        self.autoCopyOnEditorClose = autoCopyOnEditorClose
        self.maxVideoRecordingDuration = maxVideoRecordingDuration
        self.defaultRedactionStyle = defaultRedactionStyle
        self.defaultRedactionIntensity = defaultRedactionIntensity
        self.defaultStepCounterFormat = defaultStepCounterFormat
        self.showInDock = showInDock
        self.saveHistory = saveHistory
        self.maxHistoryItems = maxHistoryItems
        self.freezeScreenBeforeCapture = freezeScreenBeforeCapture
        self.captureWindowShadow = captureWindowShadow
        self.quickOverlayAutoDismiss = quickOverlayAutoDismiss
        self.quickOverlayTimeout = quickOverlayTimeout
        self.ocrOutputFormat = ocrOutputFormat
        self.ocrLLMCleanup = ocrLLMCleanup
        self.ocrCleanupModel = ocrCleanupModel
    }

    static var `default`: AppSettings {
        let desktopPath = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path ?? "~/Desktop"
        let screenshotsPath = (desktopPath as NSString).appendingPathComponent("Screenshots")

        return AppSettings(
            anthropicApiKey: "",
            openaiApiKey: "",
            llmProvider: .local,
            saveLocation: screenshotsPath,
            autoCopyToClipboard: true,
            hideDesktopIcons: false,
            hotkeys: .default,
            appearanceMode: .dark,
            launchAtStartup: false,
            imageFormat: .auto,
            jpgQuality: 0.8,
            webpQuality: 0.8,
            defaultAnnotationColor: "red",
            defaultStrokeWidth: 3.0,
            defaultAnnotationTool: "arrow",
            textAnnotationSettings: .default,
            filenameTemplate: "Lucida_{date}_{time}",
            sequentialNumber: 1,
            autoSaveOnEditorClose: false,
            autoCopyOnEditorClose: true,
            maxVideoRecordingDuration: 20,
            defaultRedactionStyle: .blur,
            defaultRedactionIntensity: 0.7,
            defaultStepCounterFormat: .numeric,
            showInDock: false,
            saveHistory: true,
            maxHistoryItems: 100,
            freezeScreenBeforeCapture: true,
            captureWindowShadow: true,
            quickOverlayAutoDismiss: true,
            quickOverlayTimeout: 5.0,
            ocrOutputFormat: .auto,
            ocrLLMCleanup: false,
            ocrCleanupModel: "gemma3:4b"
        )
    }

    /// Generate filename from template
    mutating func generateFilename(extension ext: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = dateFormatter.string(from: Date())

        dateFormatter.dateFormat = "HH-mm-ss"
        let time = dateFormatter.string(from: Date())

        let filename = filenameTemplate
            .replacingOccurrences(of: "{date}", with: date)
            .replacingOccurrences(of: "{time}", with: time)
            .replacingOccurrences(of: "{n}", with: String(format: "%04d", sequentialNumber))
            .replacingOccurrences(of: "{num}", with: String(sequentialNumber))

        // Increment sequential number
        sequentialNumber += 1

        return "\(filename).\(ext)"
    }
}

enum LLMProvider: String, Codable, CaseIterable {
    case local = "Apple Intelligence"
    case anthropic = "Anthropic"
    case openai = "OpenAI"

    var baseURL: String {
        switch self {
        case .local: return ""
        case .anthropic: return "https://api.anthropic.com/v1"
        case .openai: return "https://api.openai.com/v1"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .local: return false
        case .anthropic, .openai: return true
        }
    }
}

struct HotkeySettings: Codable {
    var areaCapture: String
    var windowCapture: String
    var fullscreenCapture: String
    var autoPasteCapture: String
    var ocrPasteCapture: String
    var allScreensCapture: String
    var scrollingCapture: String
    var ocrCapture: String
    var colorPicker: String
    var pixelRuler: String
    var timedCapture: String
    var activeWindowCapture: String
    var unifiedCapture: String
    var captureError: String
    var captureForClaude: String
    var captureCode: String
    var recaptureLastArea: String
    var smartCapture: String

    enum CodingKeys: String, CodingKey {
        case areaCapture, windowCapture, fullscreenCapture, autoPasteCapture, ocrPasteCapture, allScreensCapture
        case scrollingCapture, ocrCapture, colorPicker, pixelRuler, timedCapture, activeWindowCapture
        case unifiedCapture
        case captureError, captureForClaude, captureCode
        case recaptureLastArea, smartCapture
    }

    init(
        areaCapture: String,
        windowCapture: String,
        fullscreenCapture: String,
        autoPasteCapture: String = "⌘⇧6",
        ocrPasteCapture: String = "⌘⇧7",
        allScreensCapture: String = "⌘⇧⌥3",
        scrollingCapture: String = "⌘⇧2",
        ocrCapture: String = "⌘⇧8",
        colorPicker: String = "⌘⇧C",
        pixelRuler: String = "⌘⇧R",
        timedCapture: String = "⌘⇧T",
        activeWindowCapture: String = "⌘⇧W",
        unifiedCapture: String = "⌘⇧1",
        captureError: String = "⌘⇧E",
        captureForClaude: String = "⌘⇧F",
        captureCode: String = "⌘⇧`",
        recaptureLastArea: String = "⌘⇧L",
        smartCapture: String = "⌘⇧Space"
    ) {
        self.areaCapture = areaCapture
        self.windowCapture = windowCapture
        self.fullscreenCapture = fullscreenCapture
        self.autoPasteCapture = autoPasteCapture
        self.ocrPasteCapture = ocrPasteCapture
        self.allScreensCapture = allScreensCapture
        self.scrollingCapture = scrollingCapture
        self.ocrCapture = ocrCapture
        self.colorPicker = colorPicker
        self.pixelRuler = pixelRuler
        self.timedCapture = timedCapture
        self.activeWindowCapture = activeWindowCapture
        self.unifiedCapture = unifiedCapture
        self.captureError = captureError
        self.captureForClaude = captureForClaude
        self.captureCode = captureCode
        self.recaptureLastArea = recaptureLastArea
        self.smartCapture = smartCapture
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        areaCapture = try container.decode(String.self, forKey: .areaCapture)
        windowCapture = try container.decode(String.self, forKey: .windowCapture)
        fullscreenCapture = try container.decode(String.self, forKey: .fullscreenCapture)
        autoPasteCapture = try container.decodeIfPresent(String.self, forKey: .autoPasteCapture) ?? "⌘⇧6"
        ocrPasteCapture = try container.decodeIfPresent(String.self, forKey: .ocrPasteCapture) ?? "⌘⇧7"
        allScreensCapture = try container.decodeIfPresent(String.self, forKey: .allScreensCapture) ?? "⌘⇧⌥3"
        scrollingCapture = try container.decodeIfPresent(String.self, forKey: .scrollingCapture) ?? "⌘⇧2"
        ocrCapture = try container.decodeIfPresent(String.self, forKey: .ocrCapture) ?? "⌘⇧8"
        colorPicker = try container.decodeIfPresent(String.self, forKey: .colorPicker) ?? "⌘⇧C"
        pixelRuler = try container.decodeIfPresent(String.self, forKey: .pixelRuler) ?? "⌘⇧R"
        timedCapture = try container.decodeIfPresent(String.self, forKey: .timedCapture) ?? "⌘⇧T"
        activeWindowCapture = try container.decodeIfPresent(String.self, forKey: .activeWindowCapture) ?? "⌘⇧W"
        unifiedCapture = try container.decodeIfPresent(String.self, forKey: .unifiedCapture) ?? "⌘⇧1"
        captureError = try container.decodeIfPresent(String.self, forKey: .captureError) ?? "⌘⇧E"
        captureForClaude = try container.decodeIfPresent(String.self, forKey: .captureForClaude) ?? "⌘⇧F"
        captureCode = try container.decodeIfPresent(String.self, forKey: .captureCode) ?? "⌘⇧`"
        recaptureLastArea = try container.decodeIfPresent(String.self, forKey: .recaptureLastArea) ?? "⌘⇧L"
        smartCapture = try container.decodeIfPresent(String.self, forKey: .smartCapture) ?? "⌘⇧Space"
    }

    static var `default`: HotkeySettings {
        HotkeySettings(
            areaCapture: "⌘⇧4",
            windowCapture: "⌘⇧5",
            fullscreenCapture: "⌘⇧3",
            autoPasteCapture: "⌘⇧6",
            ocrPasteCapture: "⌘⇧7",
            allScreensCapture: "⌘⇧⌥3",
            scrollingCapture: "⌘⇧2",
            ocrCapture: "⌘⇧8",
            colorPicker: "⌘⇧C",
            pixelRuler: "⌘⇧R",
            timedCapture: "⌘⇧T",
            activeWindowCapture: "⌘⇧W",
            unifiedCapture: "⌘⇧1",
            captureError: "⌘⇧E",
            captureForClaude: "⌘⇧F",
            captureCode: "⌘⇧`",
            recaptureLastArea: "⌘⇧L",
            smartCapture: "⌘⇧Space"
        )
    }
}

// MARK: - NSColor Hex Extension
extension NSColor {
    var hexString: String {
        guard let rgbColor = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        self.init(
            srgbRed: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}

// MARK: - Lucida Project File Format (.lucida)
/// A file format that stores the screenshot image and annotations together
struct LucidaProject: Codable {
    static let fileExtension = "lucida"
    static let utType = "com.lucida.project"

    let version: Int
    let createdAt: Date
    var modifiedAt: Date
    let captureType: CaptureType
    var annotations: [Annotation]
    let imageData: Data  // PNG data of the original image

    init(screenshot: Screenshot) throws {
        self.version = 1
        self.createdAt = screenshot.capturedAt
        self.modifiedAt = Date()
        self.captureType = screenshot.captureType
        self.annotations = screenshot.annotations
        self.imageData = screenshot.pngData
    }

    func toScreenshot() -> Screenshot? {
        guard !imageData.isEmpty else { return nil }
        guard let image = NSImage(data: imageData) else { return nil }
        return Screenshot(
            pngData: imageData,
            imageSize: image.size,
            capturedAt: createdAt,
            captureType: captureType,
            annotations: annotations
        )
    }

    /// Save project to file
    func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        try data.write(to: url)

        // Set custom file icon using thumbnail of the image
        if let thumbnailImage = createThumbnailIcon() {
            NSWorkspace.shared.setIcon(thumbnailImage, forFile: url.path, options: [])
        }
    }

    /// Create a thumbnail icon from the image data
    private func createThumbnailIcon() -> NSImage? {
        guard let originalImage = NSImage(data: imageData) else { return nil }

        let iconSize: CGFloat = 512
        let thumbnailImage = NSImage(size: NSSize(width: iconSize, height: iconSize))

        thumbnailImage.lockFocus()

        // Calculate aspect-fit size
        let originalSize = originalImage.size
        let scale = min(iconSize / originalSize.width, iconSize / originalSize.height)
        let scaledWidth = originalSize.width * scale
        let scaledHeight = originalSize.height * scale
        let xOffset = (iconSize - scaledWidth) / 2
        let yOffset = (iconSize - scaledHeight) / 2

        // Draw rounded rect background (slightly darker)
        let bgRect = NSRect(x: 8, y: 8, width: iconSize - 16, height: iconSize - 16)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 24, yRadius: 24)
        NSColor(white: 0.15, alpha: 1.0).setFill()
        bgPath.fill()

        // Draw the image scaled to fit
        let imageRect = NSRect(
            x: max(xOffset, 16),
            y: max(yOffset, 16),
            width: min(scaledWidth, iconSize - 32),
            height: min(scaledHeight, iconSize - 32)
        )

        // Clip to rounded rect
        let clipPath = NSBezierPath(roundedRect: imageRect, xRadius: 12, yRadius: 12)
        clipPath.addClip()
        originalImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1.0)

        thumbnailImage.unlockFocus()

        return thumbnailImage
    }

    /// Load project from file
    static func load(from url: URL) throws -> LucidaProject {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LucidaProject.self, from: data)
    }
}

enum LucidaProjectError: Error, LocalizedError {
    case imageConversionFailed
    case invalidFileFormat

    var errorDescription: String? {
        switch self {
        case .imageConversionFailed:
            return "Failed to convert image to PNG format"
        case .invalidFileFormat:
            return "Invalid Lucida project file"
        }
    }
}
