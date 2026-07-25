import AppKit

/// A small self-dismissing message panel. Used instead of `UNUserNotificationCenter`, which
/// needs a fully registered bundle identity that an ad-hoc signed app doesn't reliably get.
@MainActor
enum HUD {
    private static var panel: NSPanel?
    private static var dismissTask: Task<Void, Never>?

    static func show(_ title: String, detail: String? = nil, duration: TimeInterval = 2.0) {
        hide()

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        label.alignment = .center

        let stack = NSStackView(views: [label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 22, bottom: 16, right: 22)

        if let detail, !detail.isEmpty {
            let sub = NSTextField(labelWithString: detail)
            sub.font = .systemFont(ofSize: 11)
            sub.textColor = .secondaryLabelColor
            sub.alignment = .center
            sub.lineBreakMode = .byTruncatingMiddle
            sub.maximumNumberOfLines = 1
            sub.preferredMaxLayoutWidth = 360
            stack.addArrangedSubview(sub)
        }

        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14

        let content = NSView()
        content.addSubview(effect)
        content.addSubview(stack)
        effect.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            effect.topAnchor.constraint(equalTo: content.topAnchor),
            effect.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            effect.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])

        let size = content.fittingSize
        let newPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        newPanel.contentView = content
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.level = .statusBar
        newPanel.ignoresMouseEvents = true
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        if let screen = screenUnderMouse() {
            let frame = screen.visibleFrame
            newPanel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height - 80
            ))
        }

        newPanel.orderFrontRegardless()
        panel = newPanel

        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    static func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    static func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
