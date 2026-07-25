import AppKit
import SwiftUI

/// Borderless panels refuse key status by default, which would break Esc and the number keys.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Presented when a scan turns up more than one code, so the user picks which payload lands
/// on the clipboard.
@MainActor
final class PickerPanel {
    private var panel: NSPanel?

    func show(results: [QRResult], onSelect: @escaping (QRResult) -> Void) {
        close()

        let view = PickerView(
            results: results,
            onSelect: { [weak self] result in
                self?.close()
                onSelect(result)
            },
            onCancel: { [weak self] in self?.close() }
        )

        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)

        let newPanel = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.contentView = hosting
        newPanel.titlebarAppearsTransparent = true
        newPanel.titleVisibility = .hidden
        newPanel.isMovableByWindowBackground = true
        newPanel.level = .floating
        newPanel.hidesOnDeactivate = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = HUD.screenUnderMouse() {
            let frame = screen.visibleFrame
            let size = hosting.fittingSize
            newPanel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.midY - size.height / 2
            ))
        }

        panel = newPanel
        NSApp.activate(ignoringOtherApps: true)
        newPanel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct PickerView: View {
    let results: [QRResult]
    let onSelect: (QRResult) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(results.count) QR codes found")
                    .font(.headline)
                Text("Choose one to copy to the clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        row(index: index, result: result)
                        if result.id != results.last?.id { Divider().padding(.leading, 44) }
                    }
                }
            }
            .frame(maxHeight: 320)

            Divider()

            HStack {
                Text("Press 1–9 to copy · Esc to dismiss")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .frame(width: 460)
        .background(
            Button("", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .hidden()
        )
    }

    @ViewBuilder
    private func row(index: Int, result: QRResult) -> some View {
        // Number-key shortcuts only make sense for the first nine rows.
        if index < 9, let char = "\(index + 1)".first {
            rowButton(index: index, result: result)
                .keyboardShortcut(KeyEquivalent(char), modifiers: [])
        } else {
            rowButton(index: index, result: result)
        }
    }

    private func rowButton(index: Int, result: QRResult) -> some View {
        Button {
            onSelect(result)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.payload)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.leading)
                    Text(result.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
