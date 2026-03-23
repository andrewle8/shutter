import Foundation
import AppKit

/// Persistent on-disk history for captured screenshots.
/// Stores PNG files in ~/Library/Application Support/Lucida/History/
/// with a JSON index for metadata.
@MainActor
class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    private let historyDir: URL
    private let indexFile: URL
    @Published private(set) var entries: [HistoryEntry] = []

    struct HistoryEntry: Codable, Identifiable {
        let id: UUID
        let capturedAt: Date
        let captureType: String // CaptureType.rawValue
        let width: Int
        let height: Int
        let filename: String // just the filename, stored in historyDir
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        historyDir = appSupport.appendingPathComponent("Lucida/History")
        indexFile = historyDir.appendingPathComponent("index.json")

        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)

        loadIndex()
    }

    // MARK: - Public API

    func save(screenshot: Screenshot) {
        let filename = "\(screenshot.id.uuidString).png"
        let fileURL = historyDir.appendingPathComponent(filename)
        try? screenshot.pngData.write(to: fileURL)

        let entry = HistoryEntry(
            id: screenshot.id,
            capturedAt: screenshot.capturedAt,
            captureType: screenshot.captureType.rawValue,
            width: Int(screenshot.imageSize.width),
            height: Int(screenshot.imageSize.height),
            filename: filename
        )
        entries.insert(entry, at: 0)
        trimAndSaveIndex()
    }

    /// Save from a background thread — writes PNG to disk without blocking main thread
    nonisolated func saveInBackground(screenshot: Screenshot) {
        let filename = "\(screenshot.id.uuidString).png"
        let fileURL = historyDir.appendingPathComponent(filename)
        try? screenshot.pngData.write(to: fileURL)

        let entry = HistoryEntry(
            id: screenshot.id,
            capturedAt: screenshot.capturedAt,
            captureType: screenshot.captureType.rawValue,
            width: Int(screenshot.imageSize.width),
            height: Int(screenshot.imageSize.height),
            filename: filename
        )

        DispatchQueue.main.async { [weak self] in
            self?.entries.insert(entry, at: 0)
            self?.trimAndSaveIndex()
        }
    }

    private func trimAndSaveIndex() {
        let max = SettingsManager.shared.settings.maxHistoryItems
        if entries.count > max {
            let removed = entries.suffix(from: max)
            for old in removed {
                try? FileManager.default.removeItem(at: historyDir.appendingPathComponent(old.filename))
            }
            entries = Array(entries.prefix(max))
        }
        saveIndex()
    }

    func loadScreenshot(for entry: HistoryEntry) -> Screenshot? {
        let fileURL = historyDir.appendingPathComponent(entry.filename)
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return nil }
        guard let image = NSImage(data: data) else { return nil }

        let captureType = CaptureType(rawValue: entry.captureType) ?? .area

        return Screenshot(
            id: entry.id,
            pngData: data,
            imageSize: image.size,
            capturedAt: entry.capturedAt,
            captureType: captureType
        )
    }

    func delete(id: UUID) {
        if let index = entries.firstIndex(where: { $0.id == id }) {
            let entry = entries[index]
            try? FileManager.default.removeItem(at: historyDir.appendingPathComponent(entry.filename))
            entries.remove(at: index)
            saveIndex()
        }
    }

    func clearAll() {
        for entry in entries {
            try? FileManager.default.removeItem(at: historyDir.appendingPathComponent(entry.filename))
        }
        entries.removeAll()
        saveIndex()
    }

    /// Load persisted history entries into the in-memory recentCaptures of ScreenCaptureService.
    /// Called once at app launch so the menu bar popover shows previous captures.
    func loadIntoRecentCaptures() {
        let service = ScreenCaptureService.shared
        // Load up to 10 most recent for the popover
        let toLoad = entries.prefix(10)
        var loaded: [Screenshot] = []
        for entry in toLoad {
            if let screenshot = loadScreenshot(for: entry) {
                loaded.append(screenshot)
            }
        }
        service.recentCaptures = loaded
    }

    // MARK: - Private

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([HistoryEntry].self, from: data)) ?? []
    }

    private func saveIndex() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: indexFile, options: .atomic)
    }
}
