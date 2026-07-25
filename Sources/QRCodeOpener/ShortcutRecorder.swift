import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click-to-record shortcut field. While recording it swallows every key combination so the
/// keystroke is captured rather than acted on.
final class ShortcutRecorderView: NSView {
    var onCapture: ((Shortcut) -> Void)?
    /// Fires when recording starts/stops so the caller can suspend the live global hotkey —
    /// otherwise pressing the currently bound combo triggers a scan instead of being recorded.
    var onRecordingChanged: ((Bool) -> Void)?

    var shortcut: Shortcut {
        didSet { updateLabel() }
    }

    private var isRecording = false {
        didSet {
            updateLabel()
            needsDisplay = true
            onRecordingChanged?(isRecording)
        }
    }

    /// Modifiers held down so far, shown as a live preview while the user is mid-chord.
    private var pendingModifiers: NSEvent.ModifierFlags = []

    private let label = NSTextField(labelWithString: "")

    init(shortcut: Shortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.alignment = .center
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 34),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])

        updateLabel()
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            window?.makeFirstResponder(self)
            pendingModifiers = []
            isRecording = true
        }
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { stopRecording() }
        return super.resignFirstResponder()
    }

    private func stopRecording() {
        pendingModifiers = []
        isRecording = false
    }

    /// Menu key equivalents are dispatched before `keyDown`, so ⌘-combinations must be
    /// intercepted here or they would trigger menu items instead of being recorded.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        handle(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handle(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        pendingModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        updateLabel()
    }

    private func handle(_ event: NSEvent) {
        let keyCode = UInt32(event.keyCode)

        // Esc alone abandons recording and keeps the existing binding.
        if keyCode == UInt32(kVK_Escape),
           event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            stopRecording()
            return
        }

        let candidate = Shortcut(
            keyCode: keyCode,
            cocoaModifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        )

        guard candidate.hasRequiredModifier else {
            flashInvalid()
            return
        }

        stopRecording()
        onCapture?(candidate)
    }

    private func flashInvalid() {
        label.stringValue = "Add ⌘, ⌃, or ⌥"
        label.textColor = .systemRed
        NSSound.beep()
    }

    private func updateLabel() {
        label.textColor = .labelColor
        if isRecording {
            if pendingModifiers.isEmpty {
                label.stringValue = "Type shortcut…"
                label.textColor = .secondaryLabelColor
            } else {
                label.stringValue = Shortcut.modifierGlyphs(pendingModifiers)
            }
        } else {
            label.stringValue = shortcut.displayString
        }
        updateColors()
    }

    private func updateColors() {
        layer?.borderColor = isRecording
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        layer?.backgroundColor = isRecording
            ? NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            : NSColor.controlBackgroundColor.cgColor
    }

    override func updateLayer() {
        updateColors()
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut
    let onCapture: (Shortcut) -> Void
    let onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderView {
        let view = ShortcutRecorderView(shortcut: shortcut)
        view.onCapture = onCapture
        view.onRecordingChanged = onRecordingChanged
        return view
    }

    func updateNSView(_ view: ShortcutRecorderView, context: Context) {
        view.onCapture = onCapture
        view.onRecordingChanged = onRecordingChanged
        if view.shortcut != shortcut { view.shortcut = shortcut }
    }
}
