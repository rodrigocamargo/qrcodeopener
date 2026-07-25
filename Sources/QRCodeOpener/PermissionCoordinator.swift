import AppKit

/// Owns the Screen Recording permission lifecycle: the one-time launch request, denial
/// tracking, and the recovery dialog.
///
/// Two macOS behaviours shape this type:
/// - A TCC grant applies only to processes started after it was given, so a stale process
///   can never capture regardless of what System Settings shows. Recovery is always
///   "relaunch".
/// - Every ScreenCaptureKit call made while permission is undetermined re-triggers the
///   system permission prompt. Scanning must therefore stop hitting ScreenCaptureKit once
///   a denial has been observed, or a broken state degenerates into an endless prompt loop.
@MainActor
final class PermissionCoordinator {
    /// Set on the first refused capture in this process; `AppDelegate.scan()` checks it and
    /// routes straight here instead of touching ScreenCaptureKit again.
    private(set) var captureDenied = false
    private var recoveryVisible = false

    func requestAtLaunch() {
        ScreenCapture.requestPermissionIfNeeded()
    }

    func captureSucceeded() {
        captureDenied = false
    }

    func captureFailed() {
        captureDenied = true
        presentRecovery()
    }

    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    private func presentRecovery() {
        guard !recoveryVisible else { return }
        recoveryVisible = true
        defer { recoveryVisible = false }

        HUD.hide()
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "QR Code Opener can't see the screen"
        alert.informativeText = """
            Enable QR Code Opener in System Settings › Privacy & Security › Screen \
            Recording, then relaunch — macOS applies the permission only to newly \
            started apps.

            If QR Code Opener isn't in the list, click the + button there and add it \
            from the Applications folder.

            If the toggle is already on, a relaunch alone fixes it. After an app update, \
            macOS may ask you to approve again.
            """
        alert.addButton(withTitle: "Relaunch Now")
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            relaunch()
        case .alertSecondButtonReturn:
            openSystemSettings()
        default:
            break
        }
    }

    /// The old and new instances must not overlap: the Carbon hotkey registration is
    /// exclusive, so a replacement launched while this process still lives would fail to
    /// bind the shortcut. A detached shell reopens the bundle after this process has exited.
    private func relaunch() {
        let path = Bundle.main.bundlePath.replacingOccurrences(of: "\"", with: "\\\"")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; /usr/bin/open \"\(path)\""]
        try? process.run()
        NSApp.terminate(nil)
    }
}
