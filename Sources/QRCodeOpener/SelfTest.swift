import AppKit

/// `--selftest` captures once, writes the outcome to
/// `~/Library/Logs/QRCodeOpener-selftest.log`, and exits. Launch it via `open` so the
/// process gets the app bundle's TCC identity, exactly like a normal launch.
@MainActor
enum SelfTest {
    static var isRequested: Bool {
        CommandLine.arguments.contains("--selftest")
    }

    static func run() {
        Task { @MainActor in
            var lines = [
                "QRCodeOpener self test — \(Date())",
                "bundle: \(Bundle.main.bundleURL.path)",
                "preflight reports access: \(ScreenCapture.processHasAccess)",
            ]

            do {
                let image = try await ScreenCapture.captureDisplayUnderMouse()
                lines.append("capture: OK \(image.width)x\(image.height)")
                let results = QRScanner.scan(image)
                lines.append("codes found: \(results.count)")
                for result in results {
                    lines.append("  - \(result.payload)")
                }
            } catch {
                lines.append("capture: FAILED — \(error.localizedDescription)")
            }

            let url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/QRCodeOpener-selftest.log")
            try? lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }
    }
}
