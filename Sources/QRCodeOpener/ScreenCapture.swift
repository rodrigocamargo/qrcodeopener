import AppKit
import CoreGraphics
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case noPermission
    case noDisplayUnderMouse

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Screen Recording permission is required"
        case .noDisplayUnderMouse:
            return "Couldn't identify the display under the cursor"
        }
    }
}

enum ScreenCapture {
    /// Asks for Screen Recording if it has never been granted.
    ///
    /// The result is only ever used to decide whether to *prompt*. It must not gate the
    /// capture itself: `CGPreflightScreenCaptureAccess` caches its answer for the lifetime of
    /// the process, so a process that started before the grant keeps reporting `false`
    /// forever — the exact reason a freshly-granted app appeared broken.
    @discardableResult
    static func requestPermissionIfNeeded() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        CGRequestScreenCaptureAccess()
        return false
    }

    /// Whether the *current process* believes it has access. A `false` here after the user
    /// has granted permission means the process is stale and must be relaunched.
    static var processHasAccess: Bool { CGPreflightScreenCaptureAccess() }

    /// Captures the single display the mouse cursor currently sits on, at full backing
    /// resolution — QR modules on a Retina screen are only a couple of points wide, so
    /// downscaling to point size is enough to make Vision miss them.
    static func captureDisplayUnderMouse() async throws -> CGImage {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
                ?? NSScreen.main,
              let number = screen.deviceDescription[.init("NSScreenNumber")] as? NSNumber
        else { throw CaptureError.noDisplayUnderMouse }

        let displayID = CGDirectDisplayID(number.uint32Value)

        // ScreenCaptureKit refusing to enumerate content is the authoritative signal that TCC
        // denied us — it reflects the real current decision, unlike the cached preflight.
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw CaptureError.noPermission
        }

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplayUnderMouse
        }

        // Exclude our own windows so a lingering HUD can never occlude a code.
        let ownWindows = content.windows.filter {
            $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(display: display, excludingWindows: ownWindows)

        let config = SCStreamConfiguration()
        let scale = screen.backingScaleFactor
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.captureResolution = .best
        config.showsCursor = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
