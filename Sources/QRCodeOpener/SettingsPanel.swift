import AppKit
import SwiftUI

@MainActor
final class SettingsPanel: NSObject, NSWindowDelegate {
    /// Applies a candidate shortcut. Returns an error message when it can't be registered,
    /// in which case the previous binding stays in force.
    var applyShortcut: ((Shortcut) -> String?)?
    var setHotKeySuspended: ((Bool) -> Void)?

    private var window: NSWindow?
    private let model = SettingsModel()

    func show(current: Shortcut) {
        model.shortcut = current
        model.errorMessage = nil
        model.apply = { [weak self] candidate in self?.applyShortcut?(candidate) }
        model.setSuspended = { [weak self] suspended in self?.setHotKeySuspended?(suspended) }

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingView(rootView: SettingsView(model: model))
        hosting.setFrameSize(hosting.fittingSize)

        let newWindow = NSWindow(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "QR Code Opener Settings"
        newWindow.contentView = hosting
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.center()
        newWindow.level = .floating

        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // A window closed mid-recording must not leave the global hotkey suspended.
        setHotKeySuspended?(false)
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var shortcut: Shortcut = .default
    @Published var errorMessage: String?

    var apply: ((Shortcut) -> String?)?
    var setSuspended: ((Bool) -> Void)?

    func capture(_ candidate: Shortcut) {
        if let error = apply?(candidate) {
            errorMessage = error
        } else {
            shortcut = candidate
            errorMessage = nil
        }
    }

    func resetToDefault() {
        capture(.default)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Scan Shortcut")
                    .font(.headline)
                Text("Press this from anywhere to scan the screen under your cursor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 14)

            HStack(spacing: 10) {
                ShortcutRecorder(
                    shortcut: model.shortcut,
                    onCapture: { model.capture($0) },
                    onRecordingChanged: { model.setSuspended?($0) }
                )
                Button("Reset") { model.resetToDefault() }
                    .disabled(model.shortcut == .default)
                Spacer(minLength: 0)
            }

            Text(model.errorMessage ?? "Click the field, then press the keys you want.")
                .font(.caption)
                .foregroundStyle(model.errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .frame(height: 30, alignment: .top)
        }
        .padding(20)
        .frame(width: 400)
    }
}
