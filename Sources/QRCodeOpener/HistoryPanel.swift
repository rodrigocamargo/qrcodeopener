import AppKit
import SwiftUI

@MainActor
final class HistoryPanel: NSObject, NSWindowDelegate {
    /// Re-copies a past payload. Owned by AppDelegate so the clipboard write and the HUD
    /// stay in one place.
    var copyPayload: ((String) -> Void)?

    private var window: NSWindow?
    private let history: ScanHistory

    init(history: ScanHistory) {
        self.history = history
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = HistoryView(
            history: history,
            onCopy: { [weak self] payload in self?.copyPayload?(payload) },
            onClear: { [weak self] in self?.confirmClear() }
        )

        let hosting = NSHostingView(rootView: view)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Scan History"
        newWindow.contentView = hosting
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self
        newWindow.center()
        newWindow.minSize = NSSize(width: 380, height: 260)

        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }

    /// Clearing is irreversible, so it asks first.
    private func confirmClear() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Clear scan history?"
        alert.informativeText = """
            All \(history.entries.count) recorded \(history.entries.count == 1 ? "scan" : "scans") \
            will be permanently deleted. This can't be undone.
            """
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true

        if let window {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn { self?.history.clear() }
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            history.clear()
        }
    }
}

private struct HistoryView: View {
    @ObservedObject var history: ScanHistory
    let onCopy: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if history.entries.isEmpty {
                emptyState
            } else {
                list
            }

            Divider()

            HStack {
                Text(countLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear History", action: onClear)
                    .disabled(history.entries.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    private var countLabel: String {
        switch history.entries.count {
        case 0: return "No scans yet"
        case 1: return "1 scan"
        default: return "\(history.entries.count) scans"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("No scans yet")
                .font(.headline)
            Text("Codes you copy will be listed here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(history.entries) { entry in
                    HistoryRow(entry: entry, onCopy: onCopy, onDelete: { history.remove(entry) })
                    if entry.id != history.entries.last?.id {
                        Divider().padding(.leading, 14)
                    }
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: ScanHistoryEntry
    let onCopy: (String) -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isURL ? "link" : "text.alignleft")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.payload)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 5) {
                    Text(entry.subtitle)
                    Text("·")
                    Text(entry.copiedAt, format: .relative(presentation: .named))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove from history")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        .background(isHovering ? Color.primary.opacity(0.05) : .clear)
        .onHover { isHovering = $0 }
        .onTapGesture { onCopy(entry.payload) }
        .help("Click to copy again")
    }
}
