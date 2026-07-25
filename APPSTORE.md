# Mac App Store submission

Status of this repo: the **app** is App Store ready in the ways code can be — sandboxed,
correctly identified, no third-party dependencies, no network access, full icon set. What
remains needs an Apple Developer account.

**Order of operations** (each gates the next):

1. D-U-N-S number for the LLC → 2. Apple Developer Program organization enrollment →
3. Paid Applications Agreement + W-9 (EIN) + banking → 4. Bundle ID, certificates,
provisioning profile → 5. Build, sign, upload → 6. Listing + screenshots + privacy policy →
7. Submit for review.

Step 1 is the long pole. Start it today; everything else is days, not weeks.

## What's already done

| Requirement | Status |
|---|---|
| App sandbox enabled | ✅ `QRCodeOpener.entitlements`, applied by `MAS=1` builds |
| Bundle identifier | ✅ `com.robotsdrinkingtea.qrcodeopener` |
| `LSApplicationCategoryType` | ✅ `public.app-category.utilities` |
| Version + build number | ✅ `CFBundleShortVersionString` / `CFBundleVersion` |
| Copyright string | ✅ `NSHumanReadableCopyright` |
| App icon, all sizes to 1024px | ✅ generated from `AppIcon.png` by `build.sh` |
| Minimum OS declared | ✅ macOS 14.0 |
| Hardened runtime | ✅ `--options runtime`, applied by `MAS=1` builds |
| No private API, no third-party SDKs | ✅ AppKit / ScreenCaptureKit / Vision / Carbon only |

`Carbon.HIToolbox`'s `RegisterEventHotKey` is old but fully public and permitted — it is the
documented way to register a global hotkey and is used by many App Store apps.

## Blockers only you can clear

### 1. Apple Developer Program — enroll as the LLC

$99/year. To sell under **Robots Drinking Tea LLC** rather than a personal name, enroll as an
*organization*.

> **EIN is not D-U-N-S.** An EIN is an IRS tax ID; a D-U-N-S number is a Dun & Bradstreet
> business identifier. Apple uses **D-U-N-S** to verify the legal entity at enrollment. The
> EIN is still needed later, on the W-9 during tax setup, and D&B will typically ask for it
> when creating the D-U-N-S record — so having it helps, but it does not replace the D-U-N-S.

**Use a company Apple ID, not a personal one.** The Apple ID that enrolls becomes the
*Account Holder* — the only role that can accept agreements, change banking, and transfer or
close the membership. Tying that to a personal Apple ID (already carrying personal purchases,
iCloud, and Family Sharing) mixes business and personal in a way that is awkward to unpick
later. Create one at `appleid.apple.com` using an address on the LLC's domain, e.g.
`developer@robotsdrinkingtea.com`, and enable two-factor authentication.

Note that the Apple ID does **not** determine the developer name shown on the App Store —
that comes from the legal entity verified via D-U-N-S. A personal Apple ID would still
display "Robots Drinking Tea LLC"; the reason to use a company address is control and
continuity, not branding.

Organization enrollment requires all of:

- a **D-U-N-S number** for the exact legal entity name. Request free via Apple's lookup at
  `developer.apple.com/enroll/duns-lookup`. Often ~5 business days, sometimes longer.
- the LLC **legally registered and in good standing**, with the name matching the D-U-N-S
  record character for character,
- a **public website on a domain belonging to the LLC** — enrollment asks for it and Apple
  does check. This blocks people more often than the D-U-N-S does.
- **legal signing authority** to bind the company. Apple may phone to verify.

Start this first; it gates everything else and is the slowest step by far.

### 2. Paid Applications Agreement — where the EIN is used

App Store Connect → **Business**. Selling requires the Paid Applications Agreement accepted,
plus:

- **Tax forms** — the US W-9 for the LLC, which is where the **EIN** goes,
- **Banking** — an account in the LLC's name for payouts.

Apps cannot go on sale until all three show *Active*. Free apps don't need this; a paid app
does.

### 3. Distribution certificates

Local dev builds are deliberately ad-hoc signed (see `build.sh` — a self-signed certificate
makes the app invisible to TCC's Screen Recording pane, so don't try that route). For
submission you need, from the Developer portal:

- **Apple Distribution** certificate (signs the app),
- **Mac Installer Distribution** certificate (signs the `.pkg`),
- a **Mac App Store provisioning profile** for the bundle ID, embedded at
  `Contents/embedded.provisionprofile`.

Then build the MAS flavour (adds sandbox + hardened runtime) and package:

```bash
MAS=1 SIGN_IDENTITY="Apple Distribution: Robots Drinking Tea LLC (TEAMID)" ./build.sh
```

```bash
productbuild --component /Applications/QRCodeOpener.app /Applications \
  --sign "3rd Party Mac Developer Installer: Robots Drinking Tea LLC" \
  QRCodeOpener.pkg
```

### 4. Build and upload — use Xcode

**Xcode 26.6 is installed** at `/Applications/Xcode.app` (`xcode-select` points at the
Command Line Tools, so plain `xcodebuild` reports "requires Xcode" — misleading, not missing).
Point it at Xcode once:

```bash
sudo xcode-select -s /Applications/Xcode.app
```

**`QRCodeOpener.xcodeproj` exists — submit from it, never from `build.sh`.** The
hand-assembled bundle carries no `DT*` toolchain metadata (`DTSDKName`, `DTXcode`,
`DTPlatformBuild`, …) that Xcode injects and App Store Connect validation looks for, and no
embedded provisioning profile. The Xcode target handles both, plus signing and upload.

The project builds the same `Sources/QRCodeOpener/*.swift`, the same `Info.plist`, and the
same `QRCodeOpener.entitlements` as `build.sh` — there is no second copy of anything. Icons
come from `Assets.xcassets` (via `CFBundleIconName`); `build.sh` injects `CFBundleIconFile`
for its own hand-built `.icns` at assembly time.

First-time setup on this machine:

```bash
sudo xcodebuild -license accept      # Xcode's licence has never been accepted here
sudo xcode-select -s /Applications/Xcode.app
```

Then, once enrolled:

1. Open `QRCodeOpener.xcodeproj`.
2. Target → Signing & Capabilities → set **Team** to Robots Drinking Tea LLC.
   `DEVELOPMENT_TEAM` is deliberately blank in the project; Xcode fills it in.
   Leave *Automatically manage signing* on — it creates the App Store provisioning profile.
3. Confirm **App Sandbox** appears (it is already declared in the entitlements file).
4. Product → **Archive** (the scheme must be Release; Archive uses Release by default).
5. Organizer → **Distribute App** → **App Store Connect** → Upload.

Xcode's own validation runs during Distribute and will surface any metadata or entitlement
problem before Apple sees it.

### 5. App Store Connect listing

Required before review: app name, subtitle, description, keywords, support URL, **privacy
policy URL** (mandatory), age rating, and at least one screenshot at an accepted size
(1280×800, 1440×900, 2560×1600, or 2880×1800).

Privacy nutrition label: declare **Data Not Collected**. The scan history stores decoded
payloads on the user's own device only, and the app has no network entitlement, so nothing
is transmitted to you or anyone else — which is what "collected" means in Apple's definition.
Local-only storage does not need declaring, but the App Review notes should mention that
history exists, is user-clearable, and never leaves the device.

## Review risks worth planning for

**Guideline 4.2 — Minimum Functionality.** Apple rejects utilities it considers too simple.
A single-purpose menu-bar tool is exactly the category that gets this. Mitigations: lead the
description with the concrete problem it solves (QR codes on desktop screens can't be scanned
without a second device), and call out the feature set beyond the one-shot scan — a
rebindable global shortcut, the multi-code picker, and **scan history with re-copy** all
argue against "too simple". Multi-monitor scanning remains an option if more is needed.

**Screen Recording permission.** Reviewers will ask why it's needed. The answer is
straightforward — the app reads QR codes from the screen — but make sure the App Review notes
field says so explicitly, and mention that captures are never stored or transmitted.

**Copy-only behaviour is a feature, explain it.** That the app never auto-navigates is a
deliberate safety property. Say so in the description; it preempts "why doesn't it just open
the link?"

## Before each submission

1. Bump `CFBundleVersion` in `Info.plist` — App Store Connect rejects duplicate build numbers.
2. Rebuild, re-sign with the distribution identity, repackage.
3. Verify: `codesign --verify --deep --strict --verbose=2 QRCodeOpener.app`
4. Verify entitlements: `codesign -d --entitlements - --xml QRCodeOpener.app | plutil -p -`

## Not verified here

The **sandbox + ScreenCaptureKit combination has not been exercised at all**: dev builds
skip the sandbox (mandatory, because sandboxed self-/ad-hoc-signed builds are rejected by
TCC), and no Apple certificate exists on this machine yet. The very first `MAS=1` build
signed with a real Apple Distribution certificate must be tested end-to-end — install via
App Store Connect internal testing and confirm capture works under the sandbox — before
assuming the shipping configuration functions.
