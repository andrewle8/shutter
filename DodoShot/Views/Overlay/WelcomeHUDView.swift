import SwiftUI
import AppKit

// MARK: - Welcome HUD Window Controller
class WelcomeHUDWindowController {
    static let shared = WelcomeHUDWindowController()

    private var window: NSWindow?
    private var dismissTimer: Timer?
    private var isDismissing = false

    private init() {}

    /// Show the welcome HUD if this is the first launch or user hasn't dismissed it permanently
    func showIfNeeded() {
        // Don't show if user has seen it before
        guard !UserDefaults.standard.bool(forKey: "hasShownWelcomeHUD") else { return }

        // Small delay so the app finishes setting up
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.show()
        }
    }

    private func show() {
        let hudView = WelcomeHUDView {
            self.dismiss()
        }

        let hostingView = NSHostingView(rootView: hudView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 200)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.nonactivatingPanel, .hudWindow, .borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .transient]
        window.isMovableByWindowBackground = false
        window.contentView = hostingView

        // Center horizontally, position in lower third of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 210
            let y = screenFrame.minY + screenFrame.height * 0.25
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)

        // Fade in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }

        self.window = window

        // Auto-dismiss after 8 seconds
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    private func dismiss() {
        guard !isDismissing else { return }
        isDismissing = true

        dismissTimer?.invalidate()
        dismissTimer = nil

        UserDefaults.standard.set(true, forKey: "hasShownWelcomeHUD")

        guard let window = self.window else { return }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            window.close()
            self?.window = nil
        })
    }
}

// MARK: - Welcome HUD View
struct WelcomeHUDView: View {
    let onDismiss: () -> Void
    @State private var isAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("DodoShot is ready")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("Capture anything on your screen")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 14)

            // Shortcut cards
            HStack(spacing: 10) {
                ShortcutCard(
                    shortcut: "\u{2318}\u{21E7}4",
                    label: "Area",
                    icon: "rectangle.dashed",
                    color: .purple,
                    isPrimary: true
                )

                ShortcutCard(
                    shortcut: "\u{2318}\u{21E7}5",
                    label: "Window",
                    icon: "macwindow",
                    color: .blue,
                    isPrimary: false
                )

                ShortcutCard(
                    shortcut: "\u{2318}\u{21E7}3",
                    label: "Fullscreen",
                    icon: "rectangle.inset.filled",
                    color: .green,
                    isPrimary: false
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
        .frame(width: 420)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                Color(nsColor: .windowBackgroundColor).opacity(0.7)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .scaleEffect(isAppeared ? 1.0 : 0.92)
        .opacity(isAppeared ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                isAppeared = true
            }
        }
    }
}

// MARK: - Shortcut Card
private struct ShortcutCard: View {
    let shortcut: String
    let label: String
    let icon: String
    let color: Color
    let isPrimary: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(color)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary.opacity(0.8))

            Text(shortcut)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(isPrimary ? .white : color)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isPrimary ? color : color.opacity(0.15))
                )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(isPrimary ? 0.12 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(isPrimary ? 0.25 : 0.1), lineWidth: 1)
                )
        )
    }
}
