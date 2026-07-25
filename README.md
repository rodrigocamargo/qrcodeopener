# QR Code Opener

Scan every QR code on your screen and copy its link — without reaching for your phone.

A macOS menu-bar utility. Press **⇧⌘7** and the QR code you're looking at is on your
clipboard, ready to paste.

- **One code found** → copied to the clipboard, with a brief confirmation.
- **Several codes found** → a picker appears; press `1`–`9` or click to copy that one, `Esc`
  to dismiss.
- **None found** → a brief "No QR code found".

It scans only the display your mouse cursor is on.

## Why it doesn't just open the browser

A QR code on screen is untrusted input — it could come from any video, ad, or page. The app
never navigates anywhere on its own; the payload only reaches your clipboard, so you always
see the URL before you decide to visit it. Paste with ⌘V.

## Install

```bash
./build.sh
open /Applications/QRCodeOpener.app
```

macOS will ask for **Screen Recording** permission on first launch — the app can't read the
screen without it. Enable it in System Settings, then use the app's **Relaunch Now** button.
No other permissions are requested.

The app lives in the menu bar (the QR icon); there's no dock icon or window.

Requires macOS 14+. No third-party dependencies — screen capture is ScreenCaptureKit, decoding
is Apple's Vision framework.

## Changing the shortcut

Menu bar icon → **Settings…** → click the shortcut field → press the keys you want. It takes
effect immediately and persists across launches. **Reset** puts ⇧⌘7 back.

- The combination needs at least one of **⌘**, **⌃**, or **⌥**. A Shift-only hotkey would
  swallow ordinary typing system-wide, so it's rejected.
- If another app already owns the combination, the field says so and your previous shortcut
  keeps working — nothing is left unbound.
- `Esc` while recording cancels and keeps the current binding.

## Scan history

Menu bar icon → **Scan History…** (⌘Y) lists every code you've copied, newest first.

- **Click any row** to copy it again — useful when you've since copied something else.
- **Hover a row** and click ✕ to remove just that entry.
- **Clear History** wipes the list. It asks first, and can't be undone.

Copying the same code again moves it to the top rather than adding a duplicate. The list is
capped at the 200 most recent scans, so it can't grow without bound.

## Autostart at login

System Settings → General → Login Items → **+** → `/Applications/QRCodeOpener.app`

## Privacy

Everything happens on your Mac. The app makes no network connections, and the App Store
build is sandboxed with no network entitlement, so it cannot transmit anything even in
principle. Screen captures are held in memory only for the moment it takes to decode them,
and are never written to disk.

Two things are stored locally, in `UserDefaults`: your chosen keyboard shortcut, and your
scan history. **The history contains the decoded contents of codes you've copied**, which
may include private links — it never leaves your Mac, but *Clear History* removes it whenever
you want, and the list is capped at 200 entries.

## Troubleshooting

**"QR Code Opener can't see the screen."** A Screen Recording grant only applies to apps
started *after* it was given. Click **Relaunch Now** in the dialog. If the dialog keeps
returning, re-approve in System Settings — after rebuilding the app, macOS requires a fresh
approval (the build script resets the stale entry for you).

**⇧⌘7 does nothing.** Another app may have claimed the shortcut — the app says so at launch
when that happens. Use *Scan Screen* from the menu bar icon, then pick a different combination
in Settings.

**A code on screen isn't detected.** Very small or partially obscured codes can defeat the
detector. Zoom the page in and scan again.

## Distribution

See [APPSTORE.md](APPSTORE.md) for the Mac App Store submission checklist and what still
needs an Apple Developer account.

---

© 2026 Robots Drinking Tea LLC. All rights reserved.
