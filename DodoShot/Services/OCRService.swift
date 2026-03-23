import Foundation
import Vision
import AppKit

// MARK: - OCR Output Format

enum OCROutputFormat: String, Codable, CaseIterable {
    case plain = "Plain Text"
    case markdown = "Markdown"
    case auto = "Auto-detect"

    var description: String {
        rawValue
    }

    var icon: String {
        switch self {
        case .plain: return "doc.plaintext"
        case .markdown: return "doc.richtext"
        case .auto: return "sparkle.magnifyingglass"
        }
    }
}

// MARK: - Detected Content Type

enum DetectedContentType: String {
    case code = "Code"
    case table = "Table"
    case list = "List"
    case errorLog = "Error/Log"
    case prose = "Text"

    var icon: String {
        switch self {
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .table: return "tablecells"
        case .list: return "list.bullet"
        case .errorLog: return "exclamationmark.triangle"
        case .prose: return "doc.plaintext"
        }
    }
}

// MARK: - OCR Result

struct OCRResult {
    let rawText: String
    let formattedText: String
    let detectedType: DetectedContentType
    let detectedLanguage: String?
    let lineCount: Int
}

// MARK: - Text Observation with Layout

private struct LayoutObservation {
    let text: String
    let boundingBox: CGRect  // Normalized 0-1 coordinates, bottom-left origin
    let confidence: Float

    /// X position in normalized coordinates
    var xPosition: CGFloat { boundingBox.minX }
    /// Y position (flipped to top-left origin)
    var yPositionTopDown: CGFloat { 1.0 - boundingBox.maxY }
    /// Height of the text line
    var lineHeight: CGFloat { boundingBox.height }
    /// Width of the text
    var width: CGFloat { boundingBox.width }
    /// Indentation level estimated from X offset
    var indentLevel: Int {
        // Each indent level is roughly 0.03 in normalized coordinates
        let margin = 0.02  // left margin tolerance
        let indentUnit = 0.025
        let offset = max(0, Double(xPosition) - margin)
        return Int(offset / indentUnit)
    }
}

// MARK: - Line Group

private struct LineGroup {
    var observations: [LayoutObservation]

    var text: String {
        observations.sorted { $0.xPosition < $1.xPosition }
            .map(\.text)
            .joined(separator: " ")
    }

    var yPosition: CGFloat {
        observations.map(\.yPositionTopDown).min() ?? 0
    }

    var minX: CGFloat {
        observations.map(\.xPosition).min() ?? 0
    }

    var maxX: CGFloat {
        observations.map { $0.xPosition + $0.width }.max() ?? 0
    }

    var columnCount: Int {
        observations.count
    }
}

// MARK: - OCR Service

/// Service for performing OCR on images using Apple's Vision framework.
/// Provides layout-aware text extraction with format auto-detection.
class OCRService {
    static let shared = OCRService()

    private init() {}

    // MARK: - Public API

    /// Perform OCR on an image, returning a formatted result.
    /// - Parameters:
    ///   - image: The source image
    ///   - format: Output format (auto-detect by default)
    ///   - forceType: If set, overrides auto-detection (used by error/code capture hotkeys)
    ///   - completion: Called on main thread with the result
    func extractText(
        from image: NSImage,
        format: OCROutputFormat = .auto,
        forceType: DetectedContentType? = nil,
        completion: @escaping (Result<OCRResult, Error>) -> Void
    ) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.failure(OCRError.invalidImage))
            return
        }

        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        let request = VNRecognizeTextRequest { [weak self] request, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                DispatchQueue.main.async { completion(.failure(OCRError.noTextFound)) }
                return
            }

            let result = self.processObservations(
                observations,
                imageSize: imageSize,
                format: format,
                forceType: forceType
            )

            DispatchQueue.main.async {
                completion(.success(result))
            }
        }

        // Configure for maximum accuracy
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        if #available(macOS 14.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }
        // Add common programming terms to improve recognition
        request.customWords = [
            "func", "struct", "class", "enum", "protocol", "import", "return", "guard",
            "async", "await", "throws", "override", "mutating", "var", "let", "self",
            "def", "elif", "lambda", "yield", "from", "print", "None", "True", "False",
            "const", "console", "require", "module", "exports", "undefined", "null",
            "void", "static", "public", "private", "protected", "interface", "implements",
            "Traceback", "Exception", "Error", "Warning", "stderr", "stdout",
            "nil", "String", "Int", "Bool", "Double", "Float", "Array", "Dictionary",
            "println", "printf", "sprintf", "fprintf", "malloc", "sizeof",
            "npm", "pip", "cargo", "brew", "apt", "git", "ssh", "curl", "wget",
        ]

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try requestHandler.perform([request])
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    /// Legacy compatibility: extract text as plain string
    func extractText(from image: NSImage, completion: @escaping (Result<String, Error>) -> Void) {
        extractText(from: image, format: .plain, forceType: nil) { result in
            switch result {
            case .success(let ocrResult):
                completion(.success(ocrResult.formattedText))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Copy extracted text to clipboard
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    // MARK: - Layout-Aware Processing

    private func processObservations(
        _ observations: [VNRecognizedTextObservation],
        imageSize: CGSize,
        format: OCROutputFormat,
        forceType: DetectedContentType?
    ) -> OCRResult {
        // Convert to layout observations
        let layoutObs = observations.compactMap { obs -> LayoutObservation? in
            guard let candidate = obs.topCandidates(1).first else { return nil }
            return LayoutObservation(
                text: candidate.string,
                boundingBox: obs.boundingBox,
                confidence: candidate.confidence
            )
        }

        // Group into lines based on Y position
        let lines = groupIntoLines(layoutObs)
        let rawText = lines.map(\.text).joined(separator: "\n")

        // Determine content type
        let detectedType = forceType ?? detectContentType(lines: lines, rawText: rawText)

        // Format based on type and requested format
        let formatted: String
        var detectedLanguage: String? = nil

        switch format {
        case .plain:
            formatted = reconstructPlainText(lines: lines)
        case .markdown:
            (formatted, detectedLanguage) = formatAsMarkdown(lines: lines, rawText: rawText, contentType: detectedType)
        case .auto:
            switch detectedType {
            case .code:
                let (text, lang) = formatAsCode(lines: lines, rawText: rawText)
                formatted = text
                detectedLanguage = lang
            case .table:
                formatted = formatAsTable(lines: lines)
            case .list:
                formatted = formatAsList(lines: lines)
            case .errorLog:
                let (text, _) = formatAsCode(lines: lines, rawText: rawText)
                formatted = text
            case .prose:
                formatted = reconstructPlainText(lines: lines)
            }
        }

        return OCRResult(
            rawText: rawText,
            formattedText: formatted,
            detectedType: detectedType,
            detectedLanguage: detectedLanguage,
            lineCount: lines.count
        )
    }

    // MARK: - Line Grouping

    /// Group observations into lines by Y-position proximity
    private func groupIntoLines(_ observations: [LayoutObservation]) -> [LineGroup] {
        guard !observations.isEmpty else { return [] }

        // Sort by Y position (top to bottom), then X
        let sorted = observations.sorted {
            if abs($0.yPositionTopDown - $1.yPositionTopDown) < 0.005 {
                return $0.xPosition < $1.xPosition
            }
            return $0.yPositionTopDown < $1.yPositionTopDown
        }

        // Compute typical line height for grouping threshold
        let heights = sorted.map(\.lineHeight)
        let medianHeight = heights.sorted()[heights.count / 2]
        // Lines within half a median line height are considered the same line
        let yThreshold = max(medianHeight * 0.5, 0.005)

        var groups: [LineGroup] = []
        var currentGroup = LineGroup(observations: [sorted[0]])

        for i in 1..<sorted.count {
            let obs = sorted[i]
            let prevY = currentGroup.observations.last!.yPositionTopDown
            if abs(obs.yPositionTopDown - prevY) < yThreshold {
                currentGroup.observations.append(obs)
            } else {
                groups.append(currentGroup)
                currentGroup = LineGroup(observations: [obs])
            }
        }
        groups.append(currentGroup)

        return groups
    }

    // MARK: - Content Type Detection

    private func detectContentType(lines: [LineGroup], rawText: String) -> DetectedContentType {
        // Check for error/log patterns first (highest priority)
        if isErrorOrLog(rawText) {
            return .errorLog
        }

        // Check for table layout
        if isTable(lines: lines) {
            return .table
        }

        // Check for list
        if isList(lines: lines) {
            return .list
        }

        // Check for code
        if isCode(rawText: rawText, lines: lines) {
            return .code
        }

        return .prose
    }

    private func isErrorOrLog(_ text: String) -> Bool {
        let errorPatterns = [
            "Traceback", "Exception", "Error:", "ERROR", "WARN", "WARNING",
            "FATAL", "CRITICAL", "panic:", "at .*\\(.*:\\d+\\)",
            "File \".*\", line \\d+", "raise ", "throw ",
            "stack trace", "Caused by:", "Segmentation fault",
            "SIGABRT", "SIGSEGV", "Bus error", "core dumped",
            "npm ERR!", "ModuleNotFoundError", "ImportError",
            "SyntaxError", "TypeError", "ValueError", "KeyError",
            "AttributeError", "RuntimeError", "IndexError",
            "NullPointerException", "ClassNotFoundException",
            "thread '.*' panicked at",
        ]

        let lowered = text.lowercased()
        var matchCount = 0
        for pattern in errorPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if regex.firstMatch(in: text, options: [], range: range) != nil {
                    matchCount += 1
                }
            } else if lowered.contains(pattern.lowercased()) {
                matchCount += 1
            }
        }
        return matchCount >= 2
    }

    private func isTable(lines: [LineGroup]) -> Bool {
        // A table has multiple lines where each line has multiple observations
        // with consistent X positions across lines
        guard lines.count >= 3 else { return false }

        let multiColumnLines = lines.filter { $0.columnCount >= 2 }
        guard multiColumnLines.count >= 3 else { return false }

        // Check for consistent column positions
        // Collect X start positions from each multi-column line
        var xPositionSets: [[CGFloat]] = []
        for line in multiColumnLines {
            let xs = line.observations.sorted { $0.xPosition < $1.xPosition }.map(\.xPosition)
            xPositionSets.append(xs)
        }

        // Check if column positions align (within tolerance)
        let tolerance: CGFloat = 0.03
        let referenceXs = xPositionSets[0]
        var alignedCount = 0
        for xs in xPositionSets.dropFirst() {
            if xs.count == referenceXs.count {
                let aligned = zip(xs, referenceXs).allSatisfy { abs($0 - $1) < tolerance }
                if aligned { alignedCount += 1 }
            }
        }

        // If most multi-column lines align, it's a table
        return alignedCount >= multiColumnLines.count / 2
    }

    private func isList(lines: [LineGroup]) -> Bool {
        guard lines.count >= 2 else { return false }

        let listPrefixes = ["- ", "* ", "+ "]
        let texts = lines.map(\.text)

        // Check for bullet lists
        let bulletCount = texts.filter { text in
            listPrefixes.contains(where: { text.hasPrefix($0) })
        }.count

        if bulletCount >= 2 && bulletCount > texts.count / 3 {
            return true
        }

        // Check for numbered lists
        let numberedPattern = try! NSRegularExpression(pattern: "^\\d+[\\.\\)\\]] ")
        let numberedCount = texts.filter { text in
            let range = NSRange(text.startIndex..., in: text)
            return numberedPattern.firstMatch(in: text, range: range) != nil
        }.count

        return numberedCount >= 2 && numberedCount > texts.count / 3
    }

    private func isCode(rawText: String, lines: [LineGroup]) -> Bool {
        var score = 0

        // Syntactic indicators
        let codePatterns: [(String, Int)] = [
            ("\\{", 1), ("\\}", 1),
            ("\\(\\)", 1),
            ("=>", 2),
            ("->", 2),
            ("import ", 2),
            ("from .* import", 3),
            ("func ", 3),
            ("def ", 3),
            ("class ", 2),
            ("struct ", 3),
            ("let ", 2),
            ("var ", 1),
            ("const ", 2),
            ("return ", 2),
            ("if .* \\{", 2),
            ("for .* in ", 2),
            ("while .* \\{", 2),
            ("switch ", 2),
            ("case .*:", 1),
            ("print\\(", 2),
            ("console\\.log", 3),
            ("self\\.", 2),
            ("this\\.", 2),
            ("\\$\\(", 2),
            ("\\|\\|", 1),
            ("&&", 1),
            ("!=", 1),
            ("==", 1),
            ("\\+=", 1),
            ("//.*", 1),
            ("#.*", 1),
            ("\"\"\"", 2),
            ("'''", 2),
        ]

        for (pattern, weight) in codePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(rawText.startIndex..., in: rawText)
                let matches = regex.numberOfMatches(in: rawText, range: range)
                if matches > 0 {
                    score += weight * min(matches, 3)
                }
            }
        }

        // Indentation pattern: if multiple lines have consistent indentation,
        // that's a strong code signal
        let indentedLines = lines.filter { $0.observations.first?.indentLevel ?? 0 > 0 }
        if indentedLines.count >= 2 {
            score += indentedLines.count * 2
        }

        // Lines ending with semicolons
        let semicolonLines = lines.filter { $0.text.hasSuffix(";") }
        score += semicolonLines.count * 2

        // Lines ending with opening brace
        let braceLines = lines.filter { $0.text.hasSuffix("{") || $0.text.hasSuffix("}") }
        score += braceLines.count * 2

        // Threshold: 8 points = likely code
        return score >= 8
    }

    // MARK: - Language Detection

    private func detectLanguage(_ text: String) -> String? {
        struct LanguageSignal {
            let language: String
            let patterns: [String]
            let weight: Int
        }

        let signals: [LanguageSignal] = [
            // Swift
            LanguageSignal(language: "swift", patterns: [
                "\\bfunc\\b", "\\blet\\b", "\\bvar\\b", "\\bguard\\b", "\\bstruct\\b",
                "\\benum\\b", "\\bprotocol\\b", "\\b@MainActor\\b", "\\b@Published\\b",
                "\\bNSImage\\b", "\\bCGFloat\\b", "\\bDispatchQueue\\b",
            ], weight: 3),
            // Python
            LanguageSignal(language: "python", patterns: [
                "\\bdef\\b", "\\bimport\\b.*\\bfrom\\b", "\\belif\\b", "\\bself\\.",
                "\\bNone\\b", "\\bTrue\\b", "\\bFalse\\b", "\\bprint\\(",
                "\\blambda\\b", "\\byield\\b", "if __name__",
                "\\bclass\\b.*:", "\\bexcept\\b", "\\braise\\b",
            ], weight: 3),
            // JavaScript/TypeScript
            LanguageSignal(language: "javascript", patterns: [
                "\\bconst\\b", "\\bconsole\\.log\\b", "\\brequire\\(",
                "\\bmodule\\.exports\\b", "\\bundefined\\b", "\\bnull\\b",
                "=>", "\\basync\\b.*\\bawait\\b", "\\bPromise\\b",
                "\\.then\\(", "\\.catch\\(",
            ], weight: 3),
            LanguageSignal(language: "typescript", patterns: [
                "\\binterface\\b.*\\{", "\\btype\\b.*=", ": string\\b", ": number\\b",
                ": boolean\\b", "<.*>",
            ], weight: 2),
            // Rust
            LanguageSignal(language: "rust", patterns: [
                "\\bfn\\b", "\\bmut\\b", "\\bimpl\\b", "\\btrait\\b",
                "\\bpub\\b", "\\buse\\b", "\\bcrate\\b", "\\bmod\\b",
                "\\bOption<", "\\bResult<", "\\bVec<", "\\b&str\\b",
            ], weight: 3),
            // Go
            LanguageSignal(language: "go", patterns: [
                "\\bfunc\\b.*\\(.*\\).*\\{", "\\bpackage\\b", "\\bfmt\\.",
                "\\bgo\\b.*\\(", "\\bchan\\b", ":=",
                "\\bdefer\\b", "\\bgoroutine\\b",
            ], weight: 3),
            // Shell/Bash
            LanguageSignal(language: "bash", patterns: [
                "^#!/", "\\$\\{", "\\$\\(", "\\becho\\b", "\\bfi\\b",
                "\\bthen\\b", "\\belse\\b", "\\bdone\\b", "\\bwhile\\b.*\\bdo\\b",
                "\\bfor\\b.*\\bdo\\b", "\\|\\|", "&&",
            ], weight: 2),
            // Java
            LanguageSignal(language: "java", patterns: [
                "\\bpublic\\b.*\\bclass\\b", "\\bSystem\\.out\\.", "\\bvoid\\b",
                "\\bstatic\\b.*\\bvoid\\b.*\\bmain\\b", "\\bimplements\\b",
                "\\bextends\\b", "\\b@Override\\b",
            ], weight: 3),
            // C/C++
            LanguageSignal(language: "c", patterns: [
                "#include", "\\bprintf\\(", "\\bsizeof\\(", "\\bmalloc\\(",
                "\\bint\\b.*\\bmain\\b", "\\bvoid\\b.*\\*", "\\bstruct\\b.*\\{",
                "\\btypedef\\b",
            ], weight: 2),
            // Ruby
            LanguageSignal(language: "ruby", patterns: [
                "\\bputs\\b", "\\battr_accessor\\b", "\\battr_reader\\b",
                "\\bdo\\b.*\\|", "\\bend\\b$", "\\brequire\\b.*'",
                "\\bmodule\\b", "\\bclass\\b.*<",
            ], weight: 2),
        ]

        var scores: [String: Int] = [:]
        for signal in signals {
            for pattern in signal.patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) {
                    let range = NSRange(text.startIndex..., in: text)
                    let count = regex.numberOfMatches(in: text, range: range)
                    if count > 0 {
                        scores[signal.language, default: 0] += signal.weight * min(count, 5)
                    }
                }
            }
        }

        // Return the highest-scoring language if it meets a minimum threshold
        guard let best = scores.max(by: { $0.value < $1.value }), best.value >= 6 else {
            return nil
        }
        return best.key
    }

    // MARK: - Plain Text Reconstruction

    private func reconstructPlainText(lines: [LineGroup]) -> String {
        var result: [String] = []
        for line in lines {
            let sortedObs = line.observations.sorted { $0.xPosition < $1.xPosition }
            // Preserve indentation
            let indent = sortedObs.first?.indentLevel ?? 0
            let prefix = String(repeating: "  ", count: indent)
            let text = sortedObs.map(\.text).joined(separator: " ")
            result.append(prefix + text)
        }
        return result.joined(separator: "\n")
    }

    // MARK: - Markdown Formatting

    private func formatAsMarkdown(
        lines: [LineGroup],
        rawText: String,
        contentType: DetectedContentType
    ) -> (String, String?) {
        switch contentType {
        case .code, .errorLog:
            return formatAsCode(lines: lines, rawText: rawText)
        case .table:
            return (formatAsTable(lines: lines), nil)
        case .list:
            return (formatAsList(lines: lines), nil)
        case .prose:
            return (reconstructPlainText(lines: lines), nil)
        }
    }

    // MARK: - Code Formatting

    private func formatAsCode(lines: [LineGroup], rawText: String) -> (String, String?) {
        let lang = detectLanguage(rawText)
        let langTag = lang ?? ""
        let plainText = reconstructPlainText(lines: lines)
        let formatted = "```\(langTag)\n\(plainText)\n```"
        return (formatted, lang)
    }

    // MARK: - Table Formatting

    private func formatAsTable(lines: [LineGroup]) -> String {
        // Find lines with multiple columns
        let multiColLines = lines.filter { $0.columnCount >= 2 }
        guard !multiColLines.isEmpty else {
            return reconstructPlainText(lines: lines)
        }

        // Determine column count from the most common column count
        let colCounts = multiColLines.map(\.columnCount)
        let mostCommonColCount = colCounts.sorted().reduce(into: [:]) { counts, val in
            counts[val, default: 0] += 1
        }.max(by: { $0.value < $1.value })?.key ?? 2

        // Build table rows
        var rows: [[String]] = []
        for line in lines {
            let sortedObs = line.observations.sorted { $0.xPosition < $1.xPosition }
            if sortedObs.count == mostCommonColCount {
                rows.append(sortedObs.map { $0.text.trimmingCharacters(in: .whitespaces) })
            } else if sortedObs.count == 1 {
                // Single-column line: might be a header or separator
                var row = [sortedObs[0].text]
                while row.count < mostCommonColCount { row.append("") }
                rows.append(row)
            } else {
                // Try to fit into the column structure
                var row: [String] = []
                var remaining = sortedObs.map(\.text)
                while row.count < mostCommonColCount && !remaining.isEmpty {
                    row.append(remaining.removeFirst())
                }
                // Append any remaining to the last column
                if !remaining.isEmpty, !row.isEmpty {
                    row[row.count - 1] += " " + remaining.joined(separator: " ")
                }
                while row.count < mostCommonColCount { row.append("") }
                rows.append(row)
            }
        }

        guard !rows.isEmpty else { return reconstructPlainText(lines: lines) }

        // Calculate column widths
        var colWidths = Array(repeating: 0, count: mostCommonColCount)
        for row in rows {
            for (i, cell) in row.enumerated() where i < mostCommonColCount {
                colWidths[i] = max(colWidths[i], cell.count)
            }
        }
        // Minimum width of 3 for separator
        colWidths = colWidths.map { max($0, 3) }

        // Build markdown table
        var result: [String] = []

        // Header row
        let headerCells = rows[0].enumerated().map { (i, cell) in
            cell.padding(toLength: colWidths[i], withPad: " ", startingAt: 0)
        }
        result.append("| " + headerCells.joined(separator: " | ") + " |")

        // Separator
        let separatorCells = colWidths.map { String(repeating: "-", count: $0) }
        result.append("| " + separatorCells.joined(separator: " | ") + " |")

        // Data rows
        for row in rows.dropFirst() {
            let cells = row.enumerated().map { (i, cell) in
                cell.padding(toLength: colWidths[i], withPad: " ", startingAt: 0)
            }
            result.append("| " + cells.joined(separator: " | ") + " |")
        }

        return result.joined(separator: "\n")
    }

    // MARK: - List Formatting

    private func formatAsList(lines: [LineGroup]) -> String {
        var result: [String] = []
        let numberedPattern = try! NSRegularExpression(pattern: "^(\\d+)[\\.\\)\\]] (.*)")
        let bulletPrefixes = ["- ", "* ", "+ "]

        for line in lines {
            let text = line.text
            let indent = line.observations.first?.indentLevel ?? 0
            let prefix = String(repeating: "  ", count: indent)

            // Check if already a bullet
            if bulletPrefixes.contains(where: { text.hasPrefix($0) }) {
                result.append(prefix + text)
                continue
            }

            // Check if numbered
            let range = NSRange(text.startIndex..., in: text)
            if let match = numberedPattern.firstMatch(in: text, range: range) {
                let numRange = Range(match.range(at: 1), in: text)!
                let contentRange = Range(match.range(at: 2), in: text)!
                result.append(prefix + "\(text[numRange]). \(text[contentRange])")
                continue
            }

            // Plain line
            result.append(prefix + text)
        }

        return result.joined(separator: "\n")
    }

    // MARK: - Scrolling OCR Text Deduplication

    /// Merge overlapping text between consecutive OCR frames.
    /// Compares trailing lines of `existing` with leading lines of `newText`.
    static func mergeScrollingOCRText(existing: String, newText: String, overlapLines: Int = 5) -> String {
        guard !existing.isEmpty else { return newText }
        guard !newText.isEmpty else { return existing }

        let existingLines = existing.components(separatedBy: "\n")
        let newLines = newText.components(separatedBy: "\n")

        // Try to find overlap between the tail of existing and head of new
        let maxOverlap = min(overlapLines, existingLines.count, newLines.count)

        for windowSize in stride(from: maxOverlap, through: 1, by: -1) {
            let tail = Array(existingLines.suffix(windowSize))
            let head = Array(newLines.prefix(windowSize))

            // Fuzzy match: allow minor OCR differences
            if linesMatchFuzzy(tail, head) {
                let newPortion = Array(newLines.dropFirst(windowSize))
                if newPortion.isEmpty {
                    return existing
                }
                return existing + "\n" + newPortion.joined(separator: "\n")
            }
        }

        // No overlap found, just concatenate
        return existing + "\n" + newText
    }

    /// Fuzzy line comparison: lines match if they share >80% of their characters
    private static func linesMatchFuzzy(_ a: [String], _ b: [String]) -> Bool {
        guard a.count == b.count else { return false }
        for (lineA, lineB) in zip(a, b) {
            let similarity = stringSimilarity(lineA, lineB)
            if similarity < 0.8 { return false }
        }
        return true
    }

    /// Simple character-level similarity ratio
    private static func stringSimilarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0.0 }
        let maxLen = max(a.count, b.count)
        guard maxLen > 0 else { return 1.0 }

        // Count matching characters in order (LCS-like approximation)
        var matches = 0
        var bIndex = b.startIndex
        for charA in a {
            while bIndex < b.endIndex {
                if b[bIndex] == charA {
                    matches += 1
                    bIndex = b.index(after: bIndex)
                    break
                }
                bIndex = b.index(after: bIndex)
            }
        }
        return Double(matches) / Double(maxLen)
    }
}

// MARK: - OCR Errors

enum OCRError: LocalizedError {
    case invalidImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not process image for text extraction"
        case .noTextFound:
            return "No text found in image"
        }
    }
}
