import SwiftUI

// MARK: - Design Tokens
private enum Darkroom {
    static let accent = Color(red: 0x2E / 255.0, green: 0xD0 / 255.0, blue: 0x65 / 255.0) // #2ED065
    static let animDuration: Double = 0.12
    static let cardRadius: CGFloat = 14
    static let toolSize: CGFloat = 28
}

struct MenuBarView: View {
    @ObservedObject private var captureService = ScreenCaptureService.shared
    @ObservedObject private var permissionManager = PermissionManager.shared
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var showSettings = false

    var body: some View {
        Group {
            if showSettings {
                // Settings view embedded in popover
                VStack(spacing: 0) {
                    // Back button header
                    HStack {
                        Button(action: { withAnimation(.easeOut(duration: Darkroom.animDuration)) { showSettings = false } }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .semibold))
                                Text(L10n.Menu.back)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text(L10n.Menu.settings)
                            .font(.system(size: 13, weight: .semibold))

                        Spacer()
                        // Spacer to balance the back button
                        Color.clear.frame(width: 50, height: 1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    Divider()

                    SettingsView()
                }
                .frame(width: 520, height: 460)
            } else {
                // Main menu view
                VStack(spacing: 0) {
                    headerSection
                    mainCaptureSection
                    sectionDivider(label: L10n.Menu.tools)
                    toolsSection
                    quickTogglesSection
                    if !captureService.recentCaptures.isEmpty {
                        sectionDivider(label: L10n.Menu.recentCaptures)
                        recentCapturesSection
                    }
                    footerSection
                }
                .frame(width: 300)
            }
        }
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color(nsColor: .windowBackgroundColor).opacity(0.5)
            }
        )
        .preferredColorScheme(.dark)
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(spacing: 10) {
            // Aperture icon in green
            Image(systemName: "camera.aperture")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Darkroom.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text("Lucida")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text("menu.ready".localized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(permissionManager.allPermissionsGranted ? Darkroom.accent : .secondary)
            }

            Spacer()

            // Settings button
            DarkroomHeaderButton(icon: "gearshape", tooltip: L10n.Settings.general) {
                openSettings()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Main Capture Section
    private var mainCaptureSection: some View {
        VStack(spacing: 2) {
            CaptureRow(
                icon: "viewfinder",
                label: L10n.Menu.area,
                shortcut: "\u{2318}\u{21E7}4"
            ) {
                startCapture(type: .area)
            }

            CaptureRow(
                icon: "macwindow",
                label: L10n.Menu.window,
                shortcut: "\u{2318}\u{21E7}5"
            ) {
                startCapture(type: .window)
            }

            CaptureRow(
                icon: "rectangle.inset.filled",
                label: L10n.Menu.fullscreen,
                shortcut: "\u{2318}\u{21E7}3"
            ) {
                startCapture(type: .fullscreen)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Tools Section
    private var toolsSection: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                DarkroomToolButton(icon: "arrow.up.and.down.text.horizontal", tooltip: L10n.Menu.scrolling) {
                    startScrollingCapture()
                }
                DarkroomToolButton(icon: "text.viewfinder", tooltip: L10n.Menu.ocr) {
                    startOCRCapture()
                }
                DarkroomToolButton(icon: "eyedropper", tooltip: L10n.Menu.colorPicker) {
                    startColorPicker()
                }
                DarkroomToolButton(icon: "ruler", tooltip: L10n.Menu.ruler) {
                    startPixelRuler()
                }
                DarkroomToolButton(icon: "timer", tooltip: "Timed") {
                    startTimedCapture()
                }
                DarkroomToolButton(icon: "doc.on.clipboard.fill", tooltip: L10n.Menu.paste) {
                    startCaptureAndPaste()
                }
                DarkroomToolButton(icon: "doc.text.viewfinder", tooltip: L10n.Menu.ocrPaste) {
                    startOCRCaptureAndPaste()
                }
            }
            HStack(spacing: 6) {
                DarkroomToolButton(icon: "exclamationmark.triangle", tooltip: L10n.Menu.captureError) {
                    startErrorCapture()
                }
                DarkroomToolButton(icon: "terminal", tooltip: L10n.Menu.captureForClaude) {
                    startCaptureForClaude()
                }
                DarkroomToolButton(icon: "chevron.left.forwardslash.chevron.right", tooltip: L10n.Menu.captureCode) {
                    startCodeCapture()
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Quick Toggles
    private var quickTogglesSection: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)

            HStack(spacing: 16) {
                Toggle(isOn: $settingsManager.settings.autoCopyToClipboard) {
                    Text(L10n.Menu.autoCopyToggle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .toggleStyle(DarkroomToggleStyle())

                Toggle(isOn: $settingsManager.settings.hideDesktopIcons) {
                    Text(L10n.Menu.hideDesktop)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .toggleStyle(DarkroomToggleStyle())

                Toggle(isOn: $settingsManager.settings.alwaysPasteToiTerm) {
                    Text("iTerm2")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .toggleStyle(DarkroomToggleStyle())

                Toggle(isOn: $settingsManager.settings.skipEditorAfterCapture) {
                    Text("Copy only")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .toggleStyle(DarkroomToggleStyle())

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Recent Captures (Contact Sheet)
    private var recentCapturesSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(captureService.recentCaptures.prefix(6)) { screenshot in
                    ContactSheetThumbnail(screenshot: screenshot)
                }

                if captureService.recentCaptures.count > 6 {
                    ShowAllButton {
                        CaptureHistoryWindowController.shared.showHistory()
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Footer
    private var footerSection: some View {
        HStack {
            Button(action: { CaptureHistoryWindowController.shared.showHistory() }) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                    Text(L10n.Menu.history)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(0.7)

            Spacer()

            DarkroomQuitButton {
                quitApp()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Section Divider
    private func sectionDivider(label: String) -> some View {
        HStack(spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.6))
                .tracking(0.5)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Actions
    private func startCapture(type: CaptureType) {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            captureService.startCapture(type: type)
        }
    }

    private func startScrollingCapture() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ScreenCaptureService.shared.startScrollingCapture()
        }
    }

    private func startPixelRuler() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            MeasurementService.shared.startPixelRuler()
        }
    }

    private func startColorPicker() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            MeasurementService.shared.startColorPicker()
        }
    }

    private func startTimedCapture() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ScreenCaptureService.shared.showTimedCaptureModal()
        }
    }

    private func startOCRCapture() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ScreenCaptureService.shared.startOCRCapture()
        }
    }

    private func startCaptureAndPaste() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ScreenCaptureService.shared.startCaptureAndPaste(type: .area)
        }
    }

    private func startOCRCaptureAndPaste() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ScreenCaptureService.shared.startOCRCaptureAndPaste()
        }
    }

    private func startErrorCapture() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ScreenCaptureService.shared.startErrorCapture()
        }
    }

    private func startCaptureForClaude() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ScreenCaptureService.shared.startCaptureForClaude()
        }
    }

    private func startCodeCapture() {
        NSApp.sendAction(#selector(AppDelegate.closePopover), to: nil, from: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ScreenCaptureService.shared.startCodeCapture()
        }
    }

    private func openSettings() {
        withAnimation(.easeOut(duration: Darkroom.animDuration)) {
            showSettings = true
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Capture Row (horizontal row with icon, label, shortcut)
private struct CaptureRow: View {
    let icon: String
    let label: String
    let shortcut: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isHovered ? Darkroom.accent : .white.opacity(0.8))
                    .frame(width: 20, alignment: .center)

                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isHovered ? .white : .white.opacity(0.85))

                Spacer()

                Text(shortcut)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isHovered ? Darkroom.accent.opacity(0.8) : .secondary.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Darkroom.accent.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: Darkroom.animDuration)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Header Button
struct DarkroomHeaderButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered ? Darkroom.accent : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(isHovered ? Darkroom.accent.opacity(0.12) : Color.white.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeOut(duration: Darkroom.animDuration)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Tool Button (icon-only, 28x28)
private struct DarkroomToolButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isHovered ? Darkroom.accent : .secondary)
                .frame(width: Darkroom.toolSize, height: Darkroom.toolSize)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isHovered ? Darkroom.accent.opacity(0.12) : Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.white.opacity(isHovered ? 0.1 : 0.04), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .onHover { hovering in
            withAnimation(.easeOut(duration: Darkroom.animDuration)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Quit Button (dim red on hover)
private struct DarkroomQuitButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "power")
                    .font(.system(size: 11))
                Text(L10n.Menu.quit)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(isHovered ? Color.red.opacity(0.8) : .secondary)
        }
        .buttonStyle(.plain)
        .opacity(0.7)
        .onHover { hovering in
            withAnimation(.easeOut(duration: Darkroom.animDuration)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Darkroom Toggle Style (small green switch)
private struct DarkroomToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.label

            ZStack {
                Capsule()
                    .fill(configuration.isOn ? Darkroom.accent.opacity(0.5) : Color.white.opacity(0.1))
                    .frame(width: 30, height: 16)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                Circle()
                    .fill(configuration.isOn ? Darkroom.accent : Color.white.opacity(0.5))
                    .frame(width: 12, height: 12)
                    .offset(x: configuration.isOn ? 7 : -7)
                    .animation(.easeOut(duration: Darkroom.animDuration), value: configuration.isOn)
            }
            .onTapGesture {
                configuration.isOn.toggle()
            }
        }
    }
}

// MARK: - Contact Sheet Thumbnail (film strip aesthetic)
private struct ContactSheetThumbnail: View {
    let screenshot: Screenshot

    @State private var isHovered = false

    var body: some View {
        Button(action: openInEditor) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: screenshot.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 52, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(
                                isHovered ? Darkroom.accent.opacity(0.5) : Color.white.opacity(0.12),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(isHovered ? 0.3 : 0.15), radius: isHovered ? 4 : 2, y: 1)

                // Hover overlay
                if isHovered {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: 52, height: 40)

                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(4)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .onHover { hovering in
            withAnimation(.easeOut(duration: Darkroom.animDuration)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button(action: { copyToClipboard() }) {
                Label(L10n.ContextMenu.copy, systemImage: "doc.on.clipboard")
            }
            Button(action: { saveToFile() }) {
                Label(L10n.ContextMenu.save, systemImage: "square.and.arrow.down")
            }
            Button(action: { pinScreenshot() }) {
                Label(L10n.ContextMenu.pin, systemImage: "pin")
            }
            Divider()
            Button(action: { deleteScreenshot() }) {
                Label(L10n.ContextMenu.delete, systemImage: "trash")
            }
        }
    }

    private func openInEditor() {
        AnnotationEditorWindowController.shared.showEditorAndSave(for: screenshot)
    }

    private func copyToClipboard() {
        ScreenCaptureService.shared.copyToClipboard(screenshot)
    }

    private func saveToFile() {
        ScreenCaptureService.shared.saveToFile(screenshot)
    }

    private func pinScreenshot() {
        FloatingWindowService.shared.pinScreenshot(screenshot)
    }

    private func deleteScreenshot() {
        ScreenCaptureService.shared.recentCaptures.removeAll { $0.id == screenshot.id }
    }
}

// MARK: - Show All Button
struct ShowAllButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isHovered ? Darkroom.accent : .secondary)

                Text(L10n.Menu.showAll)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .frame(width: 36, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Darkroom.accent.opacity(0.08) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: Darkroom.animDuration)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Legacy components for compatibility
struct HeaderButton: View {
    let icon: String
    let tooltip: String
    let action: () -> Void

    var body: some View {
        DarkroomHeaderButton(icon: icon, tooltip: tooltip, action: action)
    }
}

struct PrimaryCaptureButton: View {
    let icon: String
    let label: String
    let shortcut: String
    let color: Color
    let action: () -> Void

    var body: some View {
        CaptureRow(icon: icon, label: label, shortcut: shortcut, action: action)
    }
}

struct MenuToolButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        DarkroomToolButton(icon: icon, tooltip: label, action: action)
    }
}

struct RecentCaptureThumbnail: View {
    let screenshot: Screenshot

    var body: some View {
        ContactSheetThumbnail(screenshot: screenshot)
    }
}

struct CaptureOptionButton: View {
    let type: CaptureType
    let action: () -> Void

    var body: some View {
        CaptureRow(
            icon: type.icon,
            label: type.rawValue,
            shortcut: type.shortcut,
            action: action
        )
    }
}

struct MeasurementMenuToolButton: View {
    let icon: String
    let label: String
    let description: String
    let gradient: [Color]
    let action: () -> Void

    var body: some View {
        DarkroomToolButton(icon: icon, tooltip: label, action: action)
    }
}

struct RecentCaptureThumb: View {
    let screenshot: Screenshot

    var body: some View {
        ContactSheetThumbnail(screenshot: screenshot)
    }
}

#Preview {
    MenuBarView()
        .frame(height: 420)
}
