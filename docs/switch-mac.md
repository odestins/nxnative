# reSwitch for Mac

Version 1.2.2 build 7 accompanies the 28 October native-runtime reliability update.
It retains the platform-specific desktop layout, keyboard/controller navigation
and Chat. This build is Developer ID signed with hardened runtime and a secure timestamp;
it is installed at `/Applications/reSwitch.app` and has not been notarized.
HOME, Settings, and the existing guest Chat connection passed delivery checks;
the library, profile, and existing preferences were preserved.
See the [28 October review and delivery](upstream-2026-10-28.md) for validation and
local package details. The earlier library, navigation and installer improvements
are recorded in the [26 October review](review-2026-10-26.md).

## reSwitch update — 26 October 2026

Earlier on 26 October, Mac 1.2.0 build 5 was installed at `/Applications/reSwitch.app`. App names, menus,
window titles, current documentation and generated Xcode projects use reSwitch.
Bundle IDs, Keychain services, game descriptors, and storage paths remain stable.
The old owned Switch.app and generated Xcode projects were moved into the cache's
`Previous` folder. The installed release retained the owner's profile, six game
cards, and restored guest Chat connection. Its Developer ID signature passes
strict verification, including both embedded Discord libraries.

The selected game title now sits directly above the horizontal cards: the scroll
area is constrained to the cards' height. All platforms share the `gamecontroller`
and `rectangle.stack` symbols. Chat has clearer connection status, a distinct Join
action, guest guidance and readable account, voice/audio, and privacy settings.

App tests passed: 29 Mac and 32 iOS; the opt-in live test is skipped in each suite.
Eight iPhone/iPad UI checks cover HOME and Chat in both orientations, larger text,
and changing microphone state through Chat Settings. The tablet conversation test
now dismisses the keyboard before closing its sheet; its repeat run passed after
an initial simulator animation stall. Eight preparation/card tests also pass; the
template test now supplies its required local save-sync package path. Mac Chat and settings were visually reviewed
with a network-free fixture; the installed guest connection was then verified.
These checks do not establish two-person voice quality or new gameplay compatibility.

The universal iPhone/iPad Release package is
`launcher/build/reSwitch-1.0.0-build17-unsigned.ipa`. It retains the mobile bundle ID
and private iCloud container. The owner subsequently explicitly requested signing
and installation: the signed build 17 was installed on both physical devices and
both launch checks passed. All existing library files and preference values were
preserved. The signed IPA is `launcher/build/reSwitch-1.0.0-build17-signed.ipa`.
Mobile delivery backups and verification are under
`~/Library/Application Support/reSwitch/Backups/build17-20261026-094356/`.
Current Mac/simulator logs are under
`~/Library/Caches/com.odestins.switch.mac/Validation-2026-10-26/reSwitch-build5-17/`.

## Previous delivery — 26 October 2026

Version 1.1.0 build 4 is installed at `/Applications/Switch.app` and passes strict
Developer ID signature verification, including the embedded SDK and Krisp library.
The Mac now uses shared native Chat, editable profile name/photo, both store choices,
DualSense HOME/navbar navigation, and a guarded power button. The owner confirmed
the connected DualSense navigation works. A saved profile edit was verified and
restored; the owner's subsequent name/photo edits remain intact.

Validation: 18 core tests, 7 Mac runtime tests, and 29 Mac app tests passed (the live
test is skipped by default). The separate live test passed real guest connection,
renewal, and restoration of the same guest on the official Mac SDK. It used an
isolated in-memory identity, never the owner's credentials. Native audio selection
tests cover input/output routing and rejecting responses after disconnect.
Installed HOME/profile/store/controller screens were inspected. A Debug-only,
network-free fixture verified Mac party/text rendering, sending, audio settings,
and the Leave Chat confirmation. The power icon exited that preview cleanly.
The running-game quit guard was retained and reviewed; no real game was stopped.
The final icon was read back through macOS Icon Services and verified without the
legacy white enclosure. The installer refreshes the bundle directory timestamp so
Icon Services does not keep an older cached icon after replacing the app.
Two-person audio, live Discord linking on this Mac, and real message/invitation
delivery remain live acceptance checks.

iPhone/iPad build 16 includes the matching controller icon and store chooser.
It passed the universal device build, 32 simulator app tests (live test skipped),
and phone portrait/landscape HOME and Chat UI checks. The archive is
`launcher/build/Switch-1.0.0-build16-unsigned.ipa`; it is intentionally unsigned and
not installed on physical devices under the repository's iOS build instructions.
The initial unsigned simulator test failed its Keychain check because the runner
lacked signing entitlements; rerunning with the normal ad-hoc simulator signature
passed. This was a test configuration issue, not a production Keychain change.

Logs are retained under
`~/Library/Caches/com.odestins.switch.mac/Validation-2026-10-26/`.

The native macOS launcher is `launcher/Mac`. It uses the same validated game-card
model as the iPhone launcher, with a separate Mac installation descriptor and
library. It requires Apple silicon and macOS 26 or later.

## Playing

Open **Applications → reSwitch**, select a cover, and choose **Start Game** (or
Command–Return). Games open in their own native windows. The launcher stays open;
**Return to Game** brings the running game forward. Only one game can be launched
at a time. Save in-game before closing its window or using **Close Game**.

The HOME design keeps the red selection/action accent, original colored navigation
icons, supplied app icon, horizontal library and Liquid Glass dock. Settings uses
normal readable text. The profile button edits your display name and photo. Settings contains the
performance HUD and full-screen launch preferences. Controllers includes the
actual runtime keyboard mappings and the separate-keyboard-player option.

Use the D-pad or left stick to select games, Down to select the navbar, and Up to
return to games. DualSense Cross opens/starts, Circle returns, and Options opens
the library. Input is suspended while typing, during modal alerts, and when reSwitch
is in the background. Store offers NSVault and ROMsNS, each opening in your browser.
The power icon quits the launcher; if a game is running, a notice asks you to save
and close it first. This uses the same quit guard as Command–Q.

The Mac-specific icon is `launcher/Mac/SwitchMac.icon`, compiled by Apple's Icon
Composer pipeline into Assets.car and an ICNS fallback. It preserves the owner's
original mark on a red face, with the system's rounded enclosure and highlights;
iPhone/iPad keep their original icon. A standalone bitmap draft was rejected after
the macOS icon renderer added a second white enclosure. The final native composition
uses the unchanged supplied artwork. The discarded built-in image-generation draft
and its exact prompt remain under `launcher/build/icon-drafts/`, outside source.

macOS can request Documents/Downloads access on the first game launch. This is
normal folder consent, separate from code signing. The launcher defers reading the
executable until play is requested and performs that work off the UI thread.

## Initial library

| Game | Version | Mac preparation |
| --- | --- | --- |
| Super Mario Bros. Wonder | 1.0.1 | Native runtime and matching shaders |
| Alan Wake Remastered | 1.0.1 | Native runtime and matching shaders |
| GYLT | 1.2 | Native runtime and matching shaders |
| HOT WHEELS UNLEASHED 2 — Turbocharged | 1.0.1 | Native runtime and matching shaders; offline only |
| Little Nightmares Complete Edition | 1.0.4 | Native runtime and matching shaders; known lighting/glyph limitations |
| Mario Tennis Aces | 1.0.0 | Card only, launch disabled; incomplete graphics and command-pool failure |

Hellblade remains excluded following the owner's removal request. Existing game
files are reused in place; there is no second copy of the large game library.
See `native-game-ports.md`, `mario-tennis-2026-10-25.md` and
`little-nightmares-2026-10-25.md` for the underlying ports' acceptance boundaries.
Successful startup is not a claim that every level or game feature works.

## Data and recovery

- Library: `~/Library/Application Support/com.odestins.switch.mac/library.json`.
  Writes are atomic; the previous valid version is kept as `.backup`. An unreadable
  primary is preserved before backup recovery. Duplicate title IDs and invalid
  paths are rejected. Covers are bounded thumbnails loaded once per session.
- Each game's build folder contains `SwitchMac.switchmac`, `MacPlayer/Runtime/dmhost`,
  `MacPlayer/save`, `MacPlayer/temp` and `MacPlayer/Logs`. The last ten launch logs
  are retained. Runtime save commits use the existing host's transactional system.
- Mac saves are **local and separate from iPhone/iPad saves**. Mac iCloud sync is
  not implemented in this version. Diagnostic checks use separate validation saves.
- Removing a card never deletes game files or saves. A moved installation can be
  relinked through the card's context menu or Game Library options.
- Add Game accepts a prepared `SwitchMac.switchmac` file, not an arbitrary NSP/XCI.
  The selected file's parent becomes the installation root. Resources and native
  executable must stay within that root, including after resolving symlinks.
- Launch uses `Process` directly, never a shell; inherited `DM_*`, `DYLD_*` and
  `MTL_*` diagnostic/injection variables are removed before supplying owned settings.

Chat compiles the same Swift views, service, credential storage, guest client and
Objective-C++ Social SDK bridge as iPhone/iPad. It reuses ArcStation's application
ID and the existing guest endpoint. No app ID, token or secret needs to be entered.
Continue as Guest or connect Discord once on the Mac. Existing mobile credentials
are not copied; accounts remain protected in each device's Keychain. Desktop OAuth
uses the SDK's normal localhost callback, preserving the existing mobile callback.

The Mac SDK owns its audio session. Chat settings includes microphone and speaker
selection; the app carries the hardened-runtime audio-input entitlement and asks
for microphone permission when starting voice. Chat continues while a game is in
front. Leave Chat, text drafts, invitations, optional account linking, connection
recovery and per-user voice controls use the shared implementation. Voice chat
itself does not provide game multiplayer. Existing native local controller slots
remain available where a game supports them; they have not been certified across
this library.

## Building and adding prepared titles

```sh
swift test --package-path launcher/Mac --scratch-path /tmp/switch-mac-tests
python3 launcher/Tools/PrepareDiscordMac.py
xcodegen generate --spec launcher/mac-project.yml
xcodebuild -project launcher/reSwitchMac.xcodeproj -scheme reSwitchMac \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/switch-mac-check \
  CODE_SIGN_IDENTITY=- test
python3 launcher/Mac/build_app.py --install /Applications/reSwitch.app
```

Pass `--identity` to use an existing Developer ID certificate. The default signature
is ad hoc for local development. The delivered local build uses Developer ID;
notarization/distribution is outside this task. The app is staged under Library/Caches
to avoid iCloud adding Finder metadata inside its signed resource seal. Previous
installed builds are kept in that cache's `Previous` folder, outside Applications.
The Mac framework is extracted from the same pinned official SDK archive as
ArcStation and embedded with its Krisp library. `reSwitchMac Live Chat` is a separate
opt-in test scheme for isolated real guest connection/renewal checks. Normal tests
use fake transports and do not send messages to real people.

After the normal NSP preparation pipeline has produced a working game, prepare its
Mac launcher descriptor and native runtime:

```sh
python3 scripts/prepare_mac_game.py \
  --card '/path/to/game/Game.iswitch' \
  --build '/path/to/game/TITLEID_build' \
  --version v65536 --install-library
```

The helper builds hosts sequentially using explicit `GAME`, signs an atomic runtime
replacement, preserves game/save data, and copies already generated font stand-ins.
`--blocked` adds an unavailable card without pretending an unfinished port is playable.
`--skip-build` is only for a runtime already prepared for that title. Do not run
simultaneous host builds: the upstream Makefile has one shared output executable.

Mac packaging does not alter the phone/iPad installations or their libraries.

## Delivery checks — 2026-10-25

- Developer ID signed app installed at `/Applications/Switch.app`; strict signature
  verification passed. Five separately built, signed native game hosts are stored
  beside their existing assets. The shader chain is `657c42552d82` for all five.
- Five runtime unit tests pass: isolated saves/settings, inherited-environment
  filtering, blocked/missing games, traversal and symlink escapes, invalid native
  executables, duplicate cards and safe library backup handling.
- HOME, Settings, arrow-key selection and unavailable Tennis state were inspected
  in the installed app. HUD preference was toggled on and returned to its default
  off. Start is disabled for Tennis. Smaller-window dragging could not be exercised
  through the computer-control session; no claim of a full resizing test.
- Direct native-host startup checks used separate `MacPlayer/Validation-*` folders,
  never phone/iPad or normal Mac saves. Mario, Alan Wake, GYLT and Little Nightmares
  stayed alive for 55 seconds and rendered captured frames. Hot Wheels stayed alive
  for 90 seconds in its repeat check and rendered its title screen, but intermittent
  display-link stalls remained. Its race performance on this Mac is not validated.
- Mario's existing conditional-rendering warning and Hot Wheels' NRR registration
  warning remain host limitations. Other games had no `[RED]` startup messages in
  these bounded checks. Full-game playthrough, live controller input and Mac save
  roundtrip have not been certified by this delivery.
- A further Mario capture verifies the restored generated button-font assets.
- Launching from the installed app can still require the owner's first-use macOS
  Documents/Downloads consent. The computer-control tool blocked access to the
  system permission dialog, so that confirmation and the final launcher-to-game
  launch check are left for the owner; the game hosts themselves were checked
  directly with the existing authorized CLI access.

Build/test/install and runtime-result summaries are retained locally under
`~/Library/Caches/com.odestins.switch.mac/Validation-2026-10-25/`; individual game
logs and captured frames remain inside each game's validation folder.
