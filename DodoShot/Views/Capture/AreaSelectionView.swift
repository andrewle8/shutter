import SwiftUI
import AppKit

// MARK: - Accent color constant
private let lucidaGreen = Color(red: 0x2E / 255.0, green: 0xD0 / 255.0, blue: 0x65 / 255.0)

struct AreaSelectionView: View {
    let onComplete: (CGRect) -> Void
    let onCancel: () -> Void
    /// Optional frozen screen image to display as background (for freeze-before-capture)
    var frozenBackground: CGImage? = nil
    /// Called when the user clicks without dragging (all-in-one: window capture)
    var onWindowClick: ((CGRect) -> Void)? = nil
    /// Called when the user presses Return (all-in-one: fullscreen capture)
    var onFullscreen: (() -> Void)? = nil

    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var isDragging = false
    @State private var mouseLocation: CGPoint = .zero
    @State private var shiftHeld = false
    @State private var spaceHeld = false
    /// Anchor recorded when Space is first pressed during a drag (used for repositioning)
    @State private var spaceDragAnchor: CGPoint?
    /// Tracks whether a real drag happened (mouse moved > threshold after mouseDown)
    @State private var didDrag = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Mouse tracking layer (must be first to receive events)
                MouseTrackingView(
                    onMouseMove: { location in
                        mouseLocation = location
                    },
                    onMouseDown: { location in
                        startPoint = location
                        currentPoint = location
                        isDragging = true
                        didDrag = false
                        spaceDragAnchor = nil
                    },
                    onMouseDragged: { location in
                        // Check if we've moved enough to count as a real drag
                        if let start = startPoint {
                            let dx = abs(location.x - start.x)
                            let dy = abs(location.y - start.y)
                            if dx > 5 || dy > 5 {
                                didDrag = true
                            }
                        }
                        handleDrag(to: location)
                    },
                    onMouseUp: { location in
                        if let start = startPoint, let current = currentPoint {
                            let rect = buildSelectionRect(from: start, to: current)
                            if didDrag && rect.width > 10 && rect.height > 10 {
                                // Normal area capture
                                onComplete(rect)
                            } else if !didDrag, let windowClick = onWindowClick {
                                // Single click with no drag: detect window under cursor
                                if let windowRect = detectWindowAtPoint(location, screenSize: geometry.size) {
                                    windowClick(windowRect)
                                } else {
                                    onCancel()
                                }
                            } else {
                                // Too small, cancel
                                onCancel()
                            }
                        }
                        isDragging = false
                        didDrag = false
                        spaceDragAnchor = nil
                    },
                    onEscape: {
                        onCancel()
                    },
                    onFlagsChanged: { flags in
                        shiftHeld = flags.contains(.shift)
                        spaceHeld = flags.contains(NSEvent.ModifierFlags(rawValue: UInt(CGEventFlags.maskSecondaryFn.rawValue))) || isSpacePressed(flags)
                    },
                    onArrowKey: { direction, shift in
                        nudgeSelection(direction: direction, shift: shift)
                    },
                    onSpaceDown: {
                        spaceHeld = true
                        // Record anchor for repositioning when Space first pressed during drag
                        if isDragging, spaceDragAnchor == nil, let current = currentPoint {
                            spaceDragAnchor = current
                        }
                    },
                    onSpaceUp: {
                        spaceHeld = false
                        spaceDragAnchor = nil
                    },
                    onReturnKey: onFullscreen
                )

                // Frozen background image (when freeze-before-capture is active)
                if let frozenBG = frozenBackground {
                    Image(nsImage: NSImage(cgImage: frozenBG, size: geometry.size))
                        .resizable()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .allowsHitTesting(false)
                }

                // Semi-transparent overlay
                Color.black.opacity(0.3)
                    .allowsHitTesting(false)

                // Selection rectangle
                if let start = startPoint, let current = currentPoint {
                    let rect = buildSelectionRect(from: start, to: current)

                    // Clear hole in overlay
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .blendMode(.destinationOut)
                        .allowsHitTesting(false)

                    // Selection border
                    SelectionBorder(rect: rect)
                        .allowsHitTesting(false)

                    // Dimension label
                    DimensionLabel(rect: rect, shiftHeld: shiftHeld)
                        .allowsHitTesting(false)
                }

                // Crosshair when not dragging
                if !isDragging {
                    CrosshairView(position: mouseLocation, size: geometry.size)
                        .allowsHitTesting(false)
                }

                // Instructions
                if !isDragging {
                    VStack {
                        if onWindowClick != nil || onFullscreen != nil {
                            InstructionBadge(text: L10n.AreaSelection.unifiedInstruction)
                                .padding(.top, 60)
                        } else {
                            InstructionBadge(text: L10n.AreaSelection.instruction)
                                .padding(.top, 60)
                        }
                        Spacer()
                    }
                    .allowsHitTesting(false)
                }
            }
            .compositingGroup()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    // MARK: - Drag handling

    private func handleDrag(to location: CGPoint) {
        guard var start = startPoint else { return }

        if spaceHeld || spaceDragAnchor != nil {
            // Space held: reposition the entire selection without resizing
            if let anchor = spaceDragAnchor {
                let dx = location.x - anchor.x
                let dy = location.y - anchor.y
                startPoint = CGPoint(x: start.x + dx, y: start.y + dy)
                currentPoint = CGPoint(x: (currentPoint?.x ?? location.x) + dx, y: (currentPoint?.y ?? location.y) + dy)
                spaceDragAnchor = location
            } else {
                spaceDragAnchor = location
            }
            return
        }

        // Normal drag (with optional shift-square constraint)
        currentPoint = location
    }

    // MARK: - Selection rect construction

    private func buildSelectionRect(from start: CGPoint, to end: CGPoint) -> CGRect {
        var dx = end.x - start.x
        var dy = end.y - start.y

        if shiftHeld && isDragging && spaceDragAnchor == nil {
            // Constrain to square: use the larger dimension
            let side = max(abs(dx), abs(dy))
            dx = dx >= 0 ? side : -side
            dy = dy >= 0 ? side : -side
        }

        let x = min(start.x, start.x + dx)
        let y = min(start.y, start.y + dy)
        let width = abs(dx)
        let height = abs(dy)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Arrow key nudge

    private func nudgeSelection(direction: ArrowDirection, shift: Bool) {
        guard let start = startPoint, let current = currentPoint else { return }
        let amount: CGFloat = shift ? 10 : 1

        var dx: CGFloat = 0
        var dy: CGFloat = 0
        switch direction {
        case .left:  dx = -amount
        case .right: dx = amount
        case .up:    dy = -amount
        case .down:  dy = amount
        }

        startPoint = CGPoint(x: start.x + dx, y: start.y + dy)
        currentPoint = CGPoint(x: current.x + dx, y: current.y + dy)
    }

    // MARK: - Window detection (all-in-one mode)

    /// Detect the window under the given point (in view coordinates, top-left origin).
    /// The point is relative to the overlay window's frame; we convert to global display coordinates
    /// for matching against CGWindowList data.
    private func detectWindowAtPoint(_ point: CGPoint, screenSize: CGSize) -> CGRect? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        let myBundleID = Bundle.main.bundleIdentifier
        let excludedOwners: Set<String> = ["Dock", "Window Server", "SystemUIServer", "Spotlight"]

        // The overlay window covers a screen. Convert point to global display coordinates.
        // point is in the view's coordinate space (top-left origin, same as CG display coords
        // once we add the screen origin). We need the screen this overlay is on.
        // The screen frame origin is in CG display coordinates (top-left of main = 0,0).
        // Our overlay window's frame matches screen.frame, so just add screen.frame.origin.
        // However we don't have direct access to the screen here. The caller (ScreenCaptureService)
        // already knows the screen. For simplicity, we find the window whose CG bounds contain our point
        // by checking all screens.

        // Get global point: iterate screens to find which one this overlay is on
        var globalPoint = point
        for screen in NSScreen.screens {
            if abs(screen.frame.size.width - screenSize.width) < 2 &&
               abs(screen.frame.size.height - screenSize.height) < 2 {
                globalPoint = CGPoint(
                    x: point.x + screen.frame.origin.x,
                    y: point.y + screen.frame.origin.y
                )
                break
            }
        }

        for dict in windowList {
            guard let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat else {
                continue
            }

            let ownerName = dict[kCGWindowOwnerName as String] as? String ?? ""
            let ownerPID = dict[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let bundleID = NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier

            // Skip our own windows, system processes, and tiny windows
            if bundleID == myBundleID { continue }
            if excludedOwners.contains(ownerName) { continue }
            if width < 100 || height < 100 { continue }

            let windowFrame = CGRect(x: x, y: y, width: width, height: height)
            if windowFrame.contains(globalPoint) {
                // Return rect in the overlay's local coordinate space (subtract screen origin)
                return CGRect(
                    x: windowFrame.origin.x - (globalPoint.x - point.x),
                    y: windowFrame.origin.y - (globalPoint.y - point.y),
                    width: windowFrame.width,
                    height: windowFrame.height
                )
            }
        }

        return nil
    }

    // MARK: - Helpers

    /// macOS does not surface Space via modifier flags; we track it via keyDown/keyUp instead.
    private func isSpacePressed(_ flags: NSEvent.ModifierFlags) -> Bool {
        return false // Space is handled via dedicated callbacks
    }
}

// MARK: - Arrow Direction
enum ArrowDirection {
    case left, right, up, down
}

// MARK: - Selection Border
struct SelectionBorder: View {
    let rect: CGRect

    var body: some View {
        ZStack {
            // Main border
            Rectangle()
                .stroke(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)

            // Corner handles
            ForEach(corners, id: \.0) { corner in
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .position(corner.1)
            }
        }
    }

    private var corners: [(String, CGPoint)] {
        [
            ("tl", CGPoint(x: rect.minX, y: rect.minY)),
            ("tr", CGPoint(x: rect.maxX, y: rect.minY)),
            ("bl", CGPoint(x: rect.minX, y: rect.maxY)),
            ("br", CGPoint(x: rect.maxX, y: rect.maxY))
        ]
    }
}

// MARK: - Dimension Label
struct DimensionLabel: View {
    let rect: CGRect
    var shiftHeld: Bool = false

    private var dimensionText: String {
        let w = Int(rect.width)
        let h = Int(rect.height)
        var text = "\(w) x \(h) px"
        if shiftHeld && w > 0 && h > 0 {
            let g = gcd(w, h)
            text += "  (\(w / g):\(h / g))"
        }
        return text
    }

    var body: some View {
        Text(dimensionText)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(lucidaGreen)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.7))
            )
            .position(x: rect.midX, y: rect.maxY + 25)
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        b == 0 ? a : gcd(b, a % b)
    }
}

// MARK: - Crosshair View
struct CrosshairView: View {
    let position: CGPoint
    let size: CGSize

    var body: some View {
        ZStack {
            // Horizontal line
            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(width: size.width, height: 1)
                .position(x: size.width / 2, y: position.y)

            // Vertical line
            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(width: 1, height: size.height)
                .position(x: position.x, y: size.height / 2)

            // Center crosshair
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 20, height: 20)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1, height: 12)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 12, height: 1)
            }
            .position(position)

            // Coordinate label near crosshair
            CoordinateLabel(position: position, screenSize: size)
        }
    }
}

// MARK: - Coordinate Label
struct CoordinateLabel: View {
    let position: CGPoint
    let screenSize: CGSize

    var body: some View {
        let text = "X: \(Int(position.x))  Y: \(Int(position.y))"

        // Position the label offset from crosshair; flip side when near edges
        let offsetX: CGFloat = position.x > screenSize.width - 140 ? -80 : 20
        let offsetY: CGFloat = position.y > screenSize.height - 40 ? -24 : 20

        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(lucidaGreen)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.75))
            )
            .position(x: position.x + offsetX, y: position.y + offsetY)
    }
}

// MARK: - Instruction Badge
struct InstructionBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.6))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Mouse Tracking NSView
struct MouseTrackingView: NSViewRepresentable {
    let onMouseMove: (CGPoint) -> Void
    let onMouseDown: (CGPoint) -> Void
    let onMouseDragged: (CGPoint) -> Void
    let onMouseUp: (CGPoint) -> Void
    let onEscape: () -> Void
    var onFlagsChanged: ((NSEvent.ModifierFlags) -> Void)? = nil
    var onArrowKey: ((ArrowDirection, Bool) -> Void)? = nil
    var onSpaceDown: (() -> Void)? = nil
    var onSpaceUp: (() -> Void)? = nil
    var onReturnKey: (() -> Void)? = nil

    func makeNSView(context: Context) -> MouseTrackingNSView {
        let view = MouseTrackingNSView()
        view.onMouseMove = onMouseMove
        view.onMouseDown = onMouseDown
        view.onMouseDragged = onMouseDragged
        view.onMouseUp = onMouseUp
        view.onEscape = onEscape
        view.onFlagsChanged = onFlagsChanged
        view.onArrowKey = onArrowKey
        view.onSpaceDown = onSpaceDown
        view.onSpaceUp = onSpaceUp
        view.onReturnKey = onReturnKey
        return view
    }

    func updateNSView(_ nsView: MouseTrackingNSView, context: Context) {}
}

class MouseTrackingNSView: NSView {
    var onMouseMove: ((CGPoint) -> Void)?
    var onMouseDown: ((CGPoint) -> Void)?
    var onMouseDragged: ((CGPoint) -> Void)?
    var onMouseUp: ((CGPoint) -> Void)?
    var onEscape: (() -> Void)?
    var onFlagsChanged: ((NSEvent.ModifierFlags) -> Void)?
    var onArrowKey: ((ArrowDirection, Bool) -> Void)?
    var onSpaceDown: (() -> Void)?
    var onSpaceUp: (() -> Void)?
    var onReturnKey: (() -> Void)?

    private var trackingArea: NSTrackingArea?
    private var spaceIsDown = false

    override var acceptsFirstResponder: Bool { true }

    // Accept mouse events even when window is not key (fixes first click issue)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true  // Accept first click even if window is not key
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )

        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Make this view the first responder immediately
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            window.makeFirstResponder(self)
            window.makeKey()
        }
    }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    override func mouseMoved(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let flippedY = bounds.height - location.y
        onMouseMove?(CGPoint(x: location.x, y: flippedY))
    }

    override func mouseDown(with event: NSEvent) {
        // Ensure we're first responder on click
        if window?.firstResponder != self {
            window?.makeFirstResponder(self)
        }
        let location = convert(event.locationInWindow, from: nil)
        let flippedY = bounds.height - location.y
        onMouseDown?(CGPoint(x: location.x, y: flippedY))
    }

    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let flippedY = bounds.height - location.y
        onMouseDragged?(CGPoint(x: location.x, y: flippedY))
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let flippedY = bounds.height - location.y
        onMouseUp?(CGPoint(x: location.x, y: flippedY))
    }

    override func flagsChanged(with event: NSEvent) {
        onFlagsChanged?(event.modifierFlags)
        super.flagsChanged(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            onEscape?()
            // Don't call super - consume the event to prevent app termination
            return
        }

        // Return/Enter key (keyCode 36) for fullscreen capture in all-in-one mode
        if event.keyCode == 36 {
            onReturnKey?()
            return
        }

        // Space key (keyCode 49) for repositioning
        if event.keyCode == 49 {
            if !spaceIsDown {
                spaceIsDown = true
                onSpaceDown?()
            }
            return
        }

        // Arrow keys for nudging selection
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 123: onArrowKey?(.left, shift); return
        case 124: onArrowKey?(.right, shift); return
        case 125: onArrowKey?(.down, shift); return
        case 126: onArrowKey?(.up, shift); return
        default: break
        }

        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { // Space released
            spaceIsDown = false
            onSpaceUp?()
            return
        }
        super.keyUp(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.keyCode == 53 { // ESC key
            onEscape?()
            return true // Event handled
        }
        return super.performKeyEquivalent(with: event)
    }
}
