import AppKit
import Carbon.HIToolbox

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var scanMenuItem: NSMenuItem?
    private var hotKey: HotKey?
    private let picker = PickerPanel()
    private let settings = SettingsPanel()
    private let permission = PermissionCoordinator()
    private let history = ScanHistory()
    private lazy var historyPanel = HistoryPanel(history: history)
    private var isScanning = false
    private var shortcut = Shortcut.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SelfTest.isRequested {
            SelfTest.run()
            return
        }

        setUpStatusItem()

        settings.applyShortcut = { [weak self] candidate in self?.apply(candidate) }
        settings.setHotKeySuspended = { [weak self] suspended in
            self?.setHotKeySuspended(suspended)
        }
        historyPanel.copyPayload = { [weak self] payload in
            self?.copyToClipboard(payload)
        }

        if !register(shortcut) {
            HUD.show(
                "Shortcut unavailable",
                detail: "\(shortcut.displayString) is claimed by another app — pick another in Settings",
                duration: 5
            )
        }

        // Prompt at launch rather than on the first scan, so the first press does something
        // useful.
        permission.requestAtLaunch()
    }

    // MARK: - Hotkey binding

    private func register(_ candidate: Shortcut) -> Bool {
        hotKey = nil // deinit unregisters the previous binding before we claim the new one
        hotKey = HotKey(
            keyCode: candidate.keyCode,
            modifiers: candidate.carbonModifiers
        ) { [weak self] in
            Task { @MainActor in self?.scan() }
        }
        if hotKey != nil { updateScanMenuItem(for: candidate) }
        return hotKey != nil
    }

    /// Returns an error message on failure, having restored the previous binding.
    private func apply(_ candidate: Shortcut) -> String? {
        guard candidate != shortcut else { return nil }

        guard register(candidate) else {
            _ = register(shortcut) // put the working binding back
            return "\(candidate.displayString) is already used by another app. Try another combination."
        }

        shortcut = candidate
        if candidate == .default {
            Shortcut.resetToDefault()
        } else {
            candidate.save()
        }
        return nil
    }

    /// Suspends the hotkey while the user is recording, so pressing the currently bound
    /// combination gets captured instead of triggering a scan.
    private func setHotKeySuspended(_ suspended: Bool) {
        if suspended {
            hotKey = nil
        } else if hotKey == nil {
            _ = register(shortcut)
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(
            systemSymbolName: "qrcode.viewfinder",
            accessibilityDescription: "QR Code Opener"
        )

        let menu = NSMenu()

        let aboutItem = NSMenuItem(
            title: "About \(About.appName)",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        let scanItem = NSMenuItem(title: "Scan Screen", action: #selector(scanFromMenu), keyEquivalent: "")
        scanItem.target = self
        menu.addItem(scanItem)
        scanMenuItem = scanItem
        updateScanMenuItem(for: shortcut)
        menu.addItem(.separator())

        let historyItem = NSMenuItem(
            title: "Scan History…",
            action: #selector(openHistory),
            keyEquivalent: "y"
        )
        historyItem.target = self
        menu.addItem(historyItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let permissionItem = NSMenuItem(
            title: "Open Screen Recording Settings…",
            action: #selector(openPrivacySettings),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit \(About.appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        item.menu = menu
        statusItem = item
    }

    /// Mirrors the live binding in the menu. Keys without a plain character (arrows, F-keys)
    /// can't be menu key equivalents, so those fall back to showing the glyphs in the title.
    private func updateScanMenuItem(for candidate: Shortcut) {
        guard let item = scanMenuItem else { return }
        let equivalent = candidate.menuKeyEquivalent
        if equivalent.isEmpty {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            item.title = "Scan Screen (\(candidate.displayString))"
        } else {
            item.keyEquivalent = equivalent
            item.keyEquivalentModifierMask = candidate.cocoaModifiers
            item.title = "Scan Screen"
        }
    }

    @objc private func scanFromMenu() {
        scan()
    }

    @objc private func openSettings() {
        settings.show(current: shortcut)
    }

    @objc private func openHistory() {
        historyPanel.show()
    }

    @objc private func showAbout() {
        About.showPanel()
    }

    @objc private func openPrivacySettings() {
        permission.openSystemSettings()
    }

    private func scan() {
        guard !isScanning else { return }

        // Once a capture has been refused, stop touching ScreenCaptureKit: every call while
        // permission is undetermined re-triggers the system prompt, and a relaunch is the
        // only thing that can change the outcome anyway.
        guard !permission.captureDenied else {
            permission.captureFailed()
            return
        }

        isScanning = true

        picker.close()
        HUD.hide()

        Task { @MainActor in
            defer { isScanning = false }

            // Give AppKit a moment to actually pull our own panels off screen before the
            // capture snapshot is taken.
            try? await Task.sleep(nanoseconds: 60_000_000)

            do {
                let image = try await ScreenCapture.captureDisplayUnderMouse()
                permission.captureSucceeded()
                handle(QRScanner.scan(image))
            } catch CaptureError.noPermission {
                permission.captureFailed()
            } catch {
                HUD.show("Scan failed", detail: error.localizedDescription, duration: 4)
            }
        }
    }

    private func handle(_ results: [QRResult]) {
        switch results.count {
        case 0:
            HUD.show("No QR code found", detail: "Nothing detected on this display")
        case 1:
            copy(results[0])
        default:
            picker.show(results: results) { [weak self] result in
                self?.copy(result)
            }
        }
    }

    private func copy(_ result: QRResult) {
        copyToClipboard(result.payload)
    }

    /// The single place anything reaches the clipboard, so history can never miss a copy.
    private func copyToClipboard(_ payload: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)
        history.record(payload)
        HUD.show("Copied to clipboard", detail: payload)
    }
}
