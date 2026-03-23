import SwiftUI
import AppKit

// MARK: - Capture History Window Controller
class CaptureHistoryWindowController {
    static let shared = CaptureHistoryWindowController()

    private var window: NSWindow?

    private init() {}

    func showHistory() {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let historyView = CaptureHistoryView()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = L10n.History.title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor.windowBackgroundColor
        window.minSize = NSSize(width: 500, height: 400)
        window.center()

        window.contentView = NSHostingView(rootView: historyView)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    func closeHistory() {
        window?.close()
        window = nil
    }
}

// MARK: - Capture History View
struct CaptureHistoryView: View {
    @ObservedObject private var captureService = ScreenCaptureService.shared
    @ObservedObject private var historyStore = HistoryStore.shared
    @State private var selectedScreenshot: Screenshot?
    @State private var searchText = ""
    @State private var filterType: CaptureTypeFilter = .all
    @State private var sortOrder: SortOrder = .newest
    @State private var viewMode: ViewMode = .grid
    @State private var loadedScreenshots: [UUID: Screenshot] = [:]

    enum CaptureTypeFilter: String, CaseIterable {
        case all
        case area
        case window
        case fullscreen

        var localizedName: String {
            switch self {
            case .all: return L10n.History.all
            case .area: return L10n.History.areas
            case .window: return L10n.History.windows
            case .fullscreen: return L10n.History.fullscreens
            }
        }
    }

    enum SortOrder: String, CaseIterable {
        case newest
        case oldest

        var localizedName: String {
            switch self {
            case .newest: return L10n.History.newest
            case .oldest: return L10n.History.oldest
            }
        }
    }

    enum ViewMode {
        case grid
        case list
    }

    var filteredEntries: [HistoryStore.HistoryEntry] {
        var items = historyStore.entries

        // Filter by type
        if filterType != .all {
            items = items.filter { entry in
                switch filterType {
                case .area: return entry.captureType == CaptureType.area.rawValue
                case .window: return entry.captureType == CaptureType.window.rawValue
                case .fullscreen: return entry.captureType == CaptureType.fullscreen.rawValue
                case .all: return true
                }
            }
        }

        // Sort
        switch sortOrder {
        case .newest:
            items = items.sorted { $0.capturedAt > $1.capturedAt }
        case .oldest:
            items = items.sorted { $0.capturedAt < $1.capturedAt }
        }

        return items
    }

    /// Load a screenshot on demand, caching it in loadedScreenshots.
    private func screenshot(for entry: HistoryStore.HistoryEntry) -> Screenshot? {
        if let cached = loadedScreenshots[entry.id] { return cached }
        if let loaded = historyStore.loadScreenshot(for: entry) {
            DispatchQueue.main.async {
                loadedScreenshots[entry.id] = loaded
            }
            return loaded
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom title bar
            titleBar

            Divider()

            // Toolbar
            toolbar

            Divider()

            // Content
            if filteredEntries.isEmpty {
                emptyState
            } else {
                if viewMode == .grid {
                    gridView
                } else {
                    listView
                }
            }

            // Status bar
            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Title Bar
    private var titleBar: some View {
        HStack(spacing: 12) {
            // App icon
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(L10n.History.title)
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(width: 180)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Toolbar
    private var toolbar: some View {
        HStack(spacing: 12) {
            // Filter picker
            Picker("Filter", selection: $filterType) {
                ForEach(CaptureTypeFilter.allCases, id: \.self) { type in
                    Text(type.localizedName).tag(type)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 280)

            Spacer()

            // Sort order
            Menu {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Button(action: { sortOrder = order }) {
                        HStack {
                            Text(order.localizedName)
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text(sortOrder.localizedName)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)

            // View mode toggle
            HStack(spacing: 0) {
                ViewModeButton(icon: "square.grid.2x2", isSelected: viewMode == .grid) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewMode = .grid
                    }
                }

                ViewModeButton(icon: "list.bullet", isSelected: viewMode == .list) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewMode = .list
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
            )

            // Clear all button
            if !historyStore.entries.isEmpty {
                Button(action: {
                    historyStore.clearAll()
                    captureService.clearRecents()
                    loadedScreenshots.removeAll()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear all history")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Grid View
    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 16)],
                spacing: 16
            ) {
                ForEach(filteredEntries) { entry in
                    if let screenshot = screenshot(for: entry) {
                        HistoryGridItem(
                            screenshot: screenshot,
                            isSelected: selectedScreenshot?.id == screenshot.id,
                            onSelect: { selectedScreenshot = screenshot },
                            onDoubleClick: { openInEditor(screenshot) },
                            onDelete: { deleteEntry(entry) }
                        )
                    } else {
                        HistoryGridPlaceholder(entry: entry)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - List View
    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredEntries) { entry in
                    if let screenshot = screenshot(for: entry) {
                        HistoryListItem(
                            screenshot: screenshot,
                            isSelected: selectedScreenshot?.id == screenshot.id,
                            onSelect: { selectedScreenshot = screenshot },
                            onDoubleClick: { openInEditor(screenshot) },
                            onDelete: { deleteEntry(entry) }
                        )
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.secondary.opacity(0.4))

            VStack(spacing: 6) {
                Text(L10n.History.noCaptures)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)

                Text(L10n.History.noCapturesDescription)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Status Bar
    private var statusBar: some View {
        HStack {
            Text("\(filteredEntries.count) capture\(filteredEntries.count == 1 ? "" : "s")")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Spacer()

            if let selected = selectedScreenshot {
                Text("\(Int(selected.imageSize.width))×\(Int(selected.imageSize.height))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - Actions
    private func openInEditor(_ screenshot: Screenshot) {
        AnnotationEditorWindowController.shared.showEditorAndSave(for: screenshot)
    }

    private func deleteEntry(_ entry: HistoryStore.HistoryEntry) {
        historyStore.delete(id: entry.id)
        captureService.recentCaptures.removeAll { $0.id == entry.id }
        loadedScreenshots.removeValue(forKey: entry.id)
        if selectedScreenshot?.id == entry.id {
            selectedScreenshot = nil
        }
    }
}

// MARK: - View Mode Button
struct ViewModeButton: View {
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isSelected ? .primary : .secondary)
                .frame(width: 28, height: 24)
                .background(isSelected ? Color.primary.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History Grid Item
// MARK: - History Grid Placeholder (for entries whose PNG hasn't loaded yet)
struct HistoryGridPlaceholder: View {
    let entry: HistoryStore.HistoryEntry

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.06))
                .frame(height: 120)
                .overlay(
                    ProgressView()
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(entry.capturedAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                Text("\(entry.width)x\(entry.height)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct HistoryGridItem: View {
    let screenshot: Screenshot
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail
            ZStack(alignment: .topTrailing) {
                Image(nsImage: screenshot.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isSelected ? Color.accentColor : Color.white.opacity(0.1),
                                lineWidth: isSelected ? 2 : 1
                            )
                    )

                // Type badge
                CaptureTypeBadge(type: screenshot.captureType)
                    .padding(6)

                // Hover overlay
                if isHovered {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.3))

                    // Quick actions
                    HStack(spacing: 8) {
                        QuickActionIcon(icon: "doc.on.clipboard") {
                            ScreenCaptureService.shared.copyToClipboard(screenshot)
                        }
                        QuickActionIcon(icon: "square.and.arrow.down") {
                            ScreenCaptureService.shared.saveToFile(screenshot)
                        }
                        QuickActionIcon(icon: "pin") {
                            FloatingWindowService.shared.pinScreenshot(screenshot)
                        }
                    }
                }
            }
            .frame(height: 120)
            .shadow(color: .black.opacity(isHovered ? 0.2 : 0.1), radius: isHovered ? 8 : 4, y: 2)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(screenshot.capturedAt))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)

                Text("\(Int(screenshot.imageSize.width))×\(Int(screenshot.imageSize.height))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .contextMenu {
            Button(action: { ScreenCaptureService.shared.copyToClipboard(screenshot) }) {
                Label(L10n.ContextMenu.copy, systemImage: "doc.on.clipboard")
            }
            Button(action: { ScreenCaptureService.shared.saveToFile(screenshot) }) {
                Label(L10n.ContextMenu.save, systemImage: "square.and.arrow.down")
            }
            Button(action: { FloatingWindowService.shared.pinScreenshot(screenshot) }) {
                Label(L10n.ContextMenu.pin, systemImage: "pin")
            }
            Divider()
            Button(role: .destructive, action: { onDelete?() }) {
                Label(L10n.ContextMenu.delete, systemImage: "trash")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - History List Item
struct HistoryListItem: View {
    let screenshot: Screenshot
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    var onDelete: (() -> Void)? = nil

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Image(nsImage: screenshot.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )

            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    CaptureTypeBadge(type: screenshot.captureType)

                    Text(formatDate(screenshot.capturedAt))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                }

                Text("\(Int(screenshot.imageSize.width))×\(Int(screenshot.imageSize.height)) • \(formatFileSize(screenshot.image))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Actions (on hover)
            if isHovered {
                HStack(spacing: 4) {
                    ListActionButton(icon: "doc.on.clipboard") {
                        ScreenCaptureService.shared.copyToClipboard(screenshot)
                    }
                    ListActionButton(icon: "square.and.arrow.down") {
                        ScreenCaptureService.shared.saveToFile(screenshot)
                    }
                    ListActionButton(icon: "pin") {
                        FloatingWindowService.shared.pinScreenshot(screenshot)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
        )
        .padding(.horizontal, 8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
        .onTapGesture(count: 1) {
            onSelect()
        }
        .contextMenu {
            Button(action: { ScreenCaptureService.shared.copyToClipboard(screenshot) }) {
                Label(L10n.ContextMenu.copy, systemImage: "doc.on.clipboard")
            }
            Button(action: { ScreenCaptureService.shared.saveToFile(screenshot) }) {
                Label(L10n.ContextMenu.save, systemImage: "square.and.arrow.down")
            }
            Button(action: { FloatingWindowService.shared.pinScreenshot(screenshot) }) {
                Label(L10n.ContextMenu.pin, systemImage: "pin")
            }
            Divider()
            Button(role: .destructive, action: { onDelete?() }) {
                Label(L10n.ContextMenu.delete, systemImage: "trash")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatFileSize(_ image: NSImage) -> String {
        guard let tiffData = image.tiffRepresentation else { return "—" }
        let bytes = tiffData.count
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - Capture Type Badge
struct CaptureTypeBadge: View {
    let type: CaptureType

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: type.icon)
                .font(.system(size: 8, weight: .semibold))

            Text(type.rawValue)
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundColor(badgeColor)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(badgeColor.opacity(0.15))
        )
    }

    private var badgeColor: Color {
        switch type {
        case .area: return .purple
        case .window: return .blue
        case .fullscreen: return .green
        }
    }
}

// MARK: - Quick Action Icon (for grid hover)
struct QuickActionIcon: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.black.opacity(isHovered ? 0.8 : 0.6))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - List Action Button
struct ListActionButton: View {
    let icon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isHovered ? .primary : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(isHovered ? 0.1 : 0.05))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    CaptureHistoryView()
        .frame(width: 720, height: 520)
}
