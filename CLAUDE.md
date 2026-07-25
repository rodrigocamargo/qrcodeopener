# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
./build.sh                 # dev build: ad-hoc signed, no sandbox, into /Applications
MAS=1 SIGN_IDENTITY="Apple Distribution: …" ./build.sh   # App Store flavour (see APPSTORE.md)
swift build -c release     # compile only (produces a bare binary that CANNOT capture the screen)
open /Applications/QRCodeOpener.app
pkill -x QRCodeOpener      # quit a running instance

# Headless end-to-end check: captures, decodes, writes a log, exits.
open -n /Applications/QRCodeOpener.app --args --selftest
cat ~/Library/Logs/QRCodeOpener-selftest.log
```

There is no test target. To exercise the decoder against a static image without launching the
GUI, compile `QRScanner.swift` alongside a throwaway `main.swift` — it has no dependency on
AppKit state or the app bundle:

```bash
swiftc -O main.swift Sources/QRCodeOpener/QRScanner.swift -o scantest && ./scantest shot.png
```

Swift requires top-level statements to live in a file literally named `main.swift`.

`Shortcut.swift` is likewise self-contained (AppKit + Carbon only) and can be exercised the
same way to check glyph rendering, modifier validation, and the UserDefaults round-trip.

Note that macOS renders modifiers in the order ⌃⌥⇧⌘, so the default shortcut displays as
**⇧⌘7**, not "⌘⇧7". Assertions on `displayString` must match that order.

## Identity

Ships as **Robots Drinking Tea LLC**, bundle ID `com.robotsdrinkingtea.qrcodeopener`. That
identifier is fixed once submitted to App Store Connect — changing it creates a different app
and orphans the TCC grant. No personal names belong in identifiers, paths, or signing.
`About.swift` is the single source for user-visible branding; everything else reads
`Info.plist`. See `APPSTORE.md` for submission state.

## Toolchain

Full **Xcode 26.6 is installed** at `/Applications/Xcode.app`, but `xcode-select` points at
`/Library/Developer/CommandLineTools`, so bare `xcodebuild` fails with a misleading "requires
Xcode" error. Either call it by full path, or switch once:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

`swift build` and `build.sh` work under either setting — they need no change.

**Two build systems, one set of sources.** Keep them in sync — never fork the source list,
`Info.plist`, or entitlements between them:

| | `build.sh` (SwiftPM) | `QRCodeOpener.xcodeproj` |
|---|---|---|
| Use for | daily development | App Store submission only |
| Signing | ad-hoc | Apple Distribution, automatic |
| Icon | generated `.icns`, `CFBundleIconFile` injected at assembly | `Assets.xcassets` via `CFBundleIconName` |
| `DT*` metadata | absent (fails App Store validation) | injected by Xcode |

`Info.plist` deliberately carries only `CFBundleIconName`; `build.sh` adds `CFBundleIconFile`
to the *copy* inside the bundle. Don't add `CFBundleIconFile` back to the source plist — the
Xcode build has no `.icns` for it to point at.

**Adding a source file** means adding it to the Xcode target too (SwiftPM picks up the
directory automatically; the project lists files explicitly).

## Architecture

A menu-bar-only agent app (`LSUIElement`, `.accessory` activation policy) with a single flow,
triggered by the user's shortcut (default ⇧⌘7) or the status-item menu:

```
HotKey → ScreenCapture.captureDisplayUnderMouse() → QRScanner.scan() → AppDelegate.handle()
                                                                        ├ 0 results → HUD
                                                                        ├ 1 result  → copyToClipboard
                                                                        └ 2+        → PickerPanel → copyToClipboard

AppDelegate.copyToClipboard() → NSPasteboard + ScanHistory.record() + HUD
```

`copyToClipboard` is the **only** path to the pasteboard — scans, picker selections, and
re-copies from the history window all funnel through it, so history can never miss a copy.

`AppDelegate` owns the whole pipeline and is the single source of truth for the live binding;
the scanning files are stateless helpers.

Shortcut rebinding (`Shortcut` / `ShortcutRecorder` / `SettingsPanel`) hangs off the same
delegate: `SettingsPanel` never touches Carbon itself, it calls back into
`AppDelegate.apply(_:)`, which is the only place that registers, persists, and rolls back.

### Deliberate choices that are easy to undo by accident

- **The `.app` bundle is load-bearing.** macOS ties the Screen Recording (TCC) grant to a
  bundled, signed identity. Running the raw SwiftPM binary yields a capture of an empty
  desktop, not an error — silent wrong behavior. Always test via the bundle.
- **Carbon `RegisterEventHotKey`, not an `NSEvent` global monitor.** The `NSEvent` route
  needs the Accessibility permission on top of Screen Recording. Carbon needs neither. The
  C callback reaches Swift through `HotKey.actions`, keyed by hotkey id.
- **Capture happens at `backingScaleFactor`, not point size.** QR modules on a Retina display
  are ~1pt wide; capturing at point resolution makes Vision miss codes entirely.
- **Copy-only by design.** The app never navigates. A QR code is untrusted input, so the
  payload only ever reaches the clipboard. `PickerPanel` selection copies, it does not open.
- **`HUD` instead of `UNUserNotificationCenter`.** User notifications need a fully registered
  bundle identity that an ad-hoc signed app does not reliably get.
- **`KeyablePanel` overrides `canBecomeKey`.** Borderless/nonactivating panels refuse key
  status by default, which silently kills Esc and the 1–9 shortcuts in the picker.
- **`HotKey.actions` stores the closure, never the `HotKey` object.** Keying the registry by
  the object would keep it alive permanently, so `deinit` would never run and every rebind
  would leak a live Carbon registration — the old shortcut would keep firing alongside the
  new one.
- **The hotkey is suspended while the recorder is open** (`setHotKeySuspended`). A Carbon
  hotkey is claimed system-wide and outranks normal key delivery, so without this, pressing
  the *currently bound* combination would trigger a scan instead of being recorded.
- **`ShortcutRecorderView` overrides `performKeyEquivalent`,** not just `keyDown`. Menu key
  equivalents are dispatched first, so ⌘-combinations would otherwise fire menu items.
- **Rebinding rolls back on failure.** `apply(_:)` re-registers the previous shortcut if the
  new one is taken, so a failed rebind never leaves the app with no working hotkey.
- **Dev builds must be ad-hoc signed — never a self-signed certificate.** TCC will not list
  an app signed with an untrusted certificate in the Screen Recording pane; the app
  re-prompts forever and can never be granted. Verified A/B with otherwise-identical
  bundles: ad-hoc appears in the pane, self-signed-cert does not. Ad-hoc's cost is that the
  designated requirement is the cdhash, so a changed binary invalidates the grant;
  `build.sh` detects the cdhash change and resets TCC so the pane never shows a stale
  enabled toggle that grants nothing. Real Apple certificates (trusted chain) are fine and
  are what MAS builds use.
- **Dev builds also skip the sandbox and hardened runtime** (`MAS=1` adds them). They are
  only meaningful under a real Apple certificate.
- **Never gate a scan on `CGPreflightScreenCaptureAccess`.** It caches per process: an app
  that started before the grant reports `false` forever. Let the capture attempt fail and
  treat `SCShareableContent` throwing as the real signal. A stale process is fixed only by
  relaunching, which is why `PermissionCoordinator` offers it.
- **Stop calling ScreenCaptureKit after a denial** (`PermissionCoordinator.captureDenied`).
  Every SCK call while permission is undetermined re-triggers the system permission prompt,
  so scanning in a denied state turns each hotkey press into a fresh OS dialog.
- **Relaunch via a detached shell** (`sleep` then `open`), never
  `createsNewApplicationInstance` while the old process lives: the Carbon hotkey is
  exclusive, so an overlapping instance fails to bind the shortcut.
- **History lives in `UserDefaults`, not a file.** The App Store build is sandboxed with no
  file entitlements; keeping the store in defaults means no container paths and no
  entitlement creep. It is capped at 200 entries because the payloads can be sensitive.
- **Payload formatting is shared** via the `String.payloadIsURL` / `payloadSubtitle`
  extension, so the picker and history rows classify links identically.
- **`SCContentFilter` excludes our own windows,** so a lingering HUD can never occlude a code;
  `AppDelegate.scan()` additionally sleeps ~60ms so AppKit finishes tearing panels down before
  the snapshot.

### Scan semantics

`QRScanner.scan` sorts by on-screen area (largest first), de-duplicates identical payloads,
and retries once on a half-scale image when the full-resolution pass finds nothing — Vision
intermittently misses codes in very large images.

## TCC gotchas

- A re-approval after any build that changes the binary is **expected** with ad-hoc signing;
  `build.sh` resets the record automatically so the pane always shows a clean prompt.
- The System Settings privacy pane caches its app list. After identity changes, quit it
  fully (⌘Q — navigating away is not enough) and reopen.
- If the app is missing from the Screen Recording pane entirely, suspect the signature
  (see the ad-hoc bullet above) — TCC registers such apps (`tccutil reset` finds a record)
  but never displays them, which looks exactly like a Settings bug and isn't.
- Debug probe: `tccutil reset ScreenCapture com.robotsdrinkingtea.qrcodeopener` succeeding
  proves TCC has a record — but the probe *deletes* it, so relaunch the app afterwards.
