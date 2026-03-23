import SwiftUI
import AppKit

// MARK: - Smart Capture Prompt View

/// Tiny floating prompt bar shown after a smart capture.
/// Displays the detected content type badge, a text field for user context,
/// and a submit button. Enter submits, Escape cancels.
struct SmartCapturePromptView: View {
    let detectedType: DetectedContentType
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var prompt: String = ""

    private let accentGreen = Color(red: 0x2E / 255.0, green: 0xD0 / 255.0, blue: 0x65 / 255.0)

    var body: some View {
        HStack(spacing: 8) {
            // Content type badge
            HStack(spacing: 4) {
                Image(systemName: detectedType.icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(detectedType.rawValue)
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(accentGreen)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accentGreen.opacity(0.15))
            .cornerRadius(6)

            // Text field (NSTextField wrapper for proper focus)
            SmartCaptureTextField(
                text: $prompt,
                placeholder: "Add context, or press Enter to paste OCR...",
                onSubmit: { onSubmit(prompt) },
                onCancel: onCancel
            )
            .frame(height: 28)

            // Submit button
            Button(action: { onSubmit(prompt) }) {
                Text("Paste")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(accentGreen)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)
    }
}

// MARK: - Visual Effect View (for dark HUD background)

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - NSTextField Wrapper (for keyboard input in NSPanel)

/// Wraps NSTextField so it can become first responder inside a floating NSPanel.
/// SwiftUI TextField does not reliably receive focus in non-activating panels.
struct SmartCaptureTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.placeholderString = placeholder
        field.font = .systemFont(ofSize: 12)
        field.textColor = .white
        field.backgroundColor = .clear
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = false
        field.lineBreakMode = .byTruncatingTail
        field.cell?.sendsActionOnEndEditing = false

        // Become first responder on next run loop to ensure the panel is ready
        DispatchQueue.main.async {
            field.window?.makeFirstResponder(field)
        }

        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        let parent: SmartCaptureTextField

        init(_ parent: SmartCaptureTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            return false
        }
    }
}
