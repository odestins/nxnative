# reSwitch launcher

Build 19 adds controller navigation, bounded image/export work, import recovery,
and Chat/save reliability improvements. It is signed with Apple Development for
the owner's registered iPhone and iPad, with verified iCloud entitlements. It has
not replaced the installed apps. See the [26 October review](review-2026-10-26.md) for
changes, validation, package paths, and remaining device checks.

The app and Xcode project are named **reSwitch**, with the user's supplied red-and-white icon. Existing bundle identifiers, Keychain services, file formats, and storage paths are retained so updates preserve libraries, saves and sign-in. To rebuild the icon from its retained source, run `swift launcher/Tools/GenerateIcon.swift launcher/Tools/IconSource.png launcher/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png`.

The `launcher/` folder contains a native SwiftUI iPhone/iPad launcher. Its HOME screen follows the Nintendo Switch 2 layout: profile and device status, a horizontal row of rounded game covers, a red selection outline, a system dock, and Options/Start controls. The accent color is the logo's sRGB red, `#E60012`. Landscape provides the console layout; portrait uses smaller cards and larger navigation controls. Artwork comes from the user's prepared games. The optional layout preview contains original sample artwork.

Platform design rule: share domain logic and brand assets, but design and review
iPhone, iPad and Mac layouts separately. iPhone needs compact portrait content and
reachable touch controls; iPad needs tablet sizing and window-aware layouts; Mac
needs desktop windows, mouse/keyboard navigation and native menus. A shared SwiftUI
view is not sufficient evidence that its layout suits every platform.

Build 18 corrects iPhone HOME: portrait covers use 44% of the available width, capped
at 190 points, and the title's controller symbol uses bold weight. The space below
the dock is capped so surplus height stays above navigation, including during Chat.
Full-size iPad card sizing remains 180–250 points, and the Mac layout is unchanged.
Separate iPhone and iPad portrait/landscape layout checks passed; the phone check
also rejects covers wider than half the screen or a navbar far above the footer.
Build 18 was signed and installed on the iPhone on 26 October 2026, and its launch
check passed. All 11 library/artwork/profile/import files and existing preference
values match the retained build 17 delivery backup. The iPad remains on build 17;
its unchanged tablet geometry passed the separate simulator check. The signed IPA
is `launcher/build/reSwitch-1.0.0-build18-signed.ipa`.

The game title uses the same controller symbol as macOS. The dock has five controls: Chat, Store, Controllers, Game Library, and Settings. Its icons retain their original colors: orange Chat, coral-red Store, and gray Controllers, Game Library, and Settings. Nintendo Online, News, GameShare, Sleep, and Album were removed at the user's request. Store offers NSVault and ROMsNS, opening the selected site in the browser. Chat connects Discord friends, messages, and party voice through the official Discord Social SDK. Profile photo selection remains available by tapping the avatar. The menu does not implement Nintendo network services or Switch 2 game compatibility.

Build 17 uses reSwitch throughout the app, the shared controller and library symbols,
and the redesigned Chat page and Chat Settings. Its universal unsigned package is
`launcher/build/reSwitch-1.0.0-build17-unsigned.ipa`. After the owner explicitly
requested signing and installation, build 17 was signed with the existing Apple
Development identity and installed in place on both the iPhone and iPad on
26 October 2026. Both remote launch checks passed. The signed delivery is
`launcher/build/reSwitch-1.0.0-build17-signed.ipa`. All 11 iPhone and four iPad
library/artwork/profile/import files matched their backups; existing preference
values were unchanged. The stable bundle ID and private iCloud entitlements remain
intact. No game app was updated.

## iPad

Build 13 adapts HOME to the available window size. Full-size iPad windows use larger covers, status text, and a centered glass dock; compact windows retain the compact layout. The dock keeps the same five icons and colors, and the active Chat bar has its own space below it. Settings, file imports, Chat, and save help identify the current device as iPad rather than iPhone. The launcher supports portrait and landscape; Mario's native app plays in landscape with its original aspect ratio.

Build 14 reduces full-size iPad covers from 350 to 250 points in both orientations. Tablet covers scale between 180 and 250 points with the window size; navigation retains its existing size.

Build 15 positions tablet navigation near the bottom, with at most 48 points between the dock/active Chat group and the Options/Start footer.

reSwitch and the prepared Mario app are universal iPhone/iPad builds. A new development device must be included in both provisioning profiles before installation. The iPad uses its own local library and Chat identity; importing a card does not copy credentials. iCloud saves use the existing shared private container when the devices use the same iCloud account. See [iPad validation](ipad-2026-10-25.md) for the physical-device results and limits.

Tap your avatar to choose, change, or remove a profile photo. Photos grants access only to the selected image. reSwitch downsamples it to a bounded JPEG, removes original camera/location metadata, and saves it locally. Changing or removing it does not modify the original in Photos.

## Settings

Settings uses readable primary text in Dark and Light mode, with red retained for switches and brand accents. The profile row opens photo and display-name controls. Gameplay groups the HUD, controller help and Chat; Games & saves groups phone imports, game cards, iCloud saves and library management. **Manage library** contains card export, layout preview and recovery. Source links and license notices are under **About reSwitch**.

Appearance changes also update the open Settings panel immediately. Larger accessibility text uses full-width labels and places the HUD switch below its explanation. Import, profile and help pages opened from Settings have a Back button.

## Performance HUD

Open **Settings → Gameplay → Performance HUD** to show or hide the frame-rate counter and Metal's frame/GPU timing and memory overlay. It is off by default, and the choice persists across launcher restarts. The setting applies when opening or resuming a game from reSwitch; a running game does not need to restart.

Game apps must be rebuilt with this version of the native integration to respond. reSwitch adds a Boolean `hud=0` or `hud=1` to its validated launch request. A cloud restore may also include a validated snapshot UUID; arbitrary file paths and runtime options remain rejected. Imported game cards cannot supply runtime options, and the native app rejects other schemes, titles, paths, or query parameters. Directly opening the game retains its last per-game choice. Hiding the frame-rate counter invalidates its timer and removes its label.

## Chat as a guest or with Discord

Open **Chat** in the dock, confirm that you meet Discord's minimum age requirement, and choose **Continue as Guest** or **Connect Discord**. Guests can start or join shared text/voice parties without a Discord login. Use **Join** with a friend's code, or start a party and share its invitation. The application ID (`1560449870496792729`), communication scopes, and pinned official Social SDK (`1.10.19337`) come from the owner's ArcStation integration. No client secret or app ID needs to be entered. The owner confirmed the mobile OAuth redirect `discord-1560449870496792729:/authorize/callback` is registered; the desktop redirect is retained.

Guest profiles use the reSwitch display name and a random device-only Keychain identity. The deployed server issues per-guest Social SDK access; the bot credential stays in a Cloudflare secret. Disconnecting retains the private guest identity for a later return. Linking Discord is optional in Chat Settings after leaving the active party, using the SDK's provisional-account merge. An unlinked guest identity does not sync between phones.

Discord's native iPhone authorization reuses the signed-in Discord app when available. It can still require one authorization on the phone. reSwitch stores its own token pair in the device-only Keychain, restores it on launch, and refreshes it when necessary. ArcStation's rotating Mac credentials are not copied. **Disconnect on this iPhone** clears the local account and drafts without revoking the shared application grant.

- **Friends / See all:** search Discord friends, read recent direct messages, send text, and block a person after confirmation. Each conversation keeps its own draft while the app remains open; a failed send preserves the draft. History is bounded to the latest messages supplied by Discord (50 direct, 100 party).
- **Start Chat / Your chat:** a shared text and voice party with participant tiles, speaking indicators, microphone mute, deafen, speaker selection, per-person volume/mute, and separate leave-voice/leave-party actions. Microphone denial leaves text available. Microphone access can be changed in Chat Settings.
- **Invite:** open People & invites → Invite friends and use the visible invitation button beside a friend, accept incoming invitations in Chat, or share a code. In reSwitch, tap **Join** beside **Start Chat** and paste the code; ArcStation also accepts shared invitation codes. Accepting an invitation or entering a code is an explicit action; opening a link alone never enables the microphone.
- **While playing:** the HOME bar retains a microphone control. Background audio is configured for voice, and updated native game apps use mixable Ambient audio so starting a game does not deliberately interrupt the chat. Background delivery and two-person audio require live device validation; see the validation record.

This is the Social SDK's friends, direct messages, and lobby communication integration. It does not browse arbitrary Discord servers/voice channels or implement Nintendo's online services, video, or screen sharing. Both voice participants need a compatible SDK client and the app must have Discord communications access. Existing application development limits still apply. No automatic real-message, invitation, or two-person-call test is performed.

The app accepts shared `switchchat://join?code=...` links and Discord-style `switchchat://game/_discord/join?secret=...` links. Launching reSwitch directly from a mobile Discord invite additionally requires the application's mobile deep-link configuration in Discord's portal; that separate setting has not been verified. In-app invitations and shared codes do not depend on that launch route. [Discord account-linking guide](https://docs.discord.com/developers/discord-social-sdk/development-guides/account-linking-on-mobile) and [mobile invite guide](https://docs.discord.com/developers/discord-social-sdk/development-guides/managing-game-invites).

## iCloud saves

Settings → Games & saves → iCloud saves shows availability, upload status, recent backups, and restore actions. The launcher and each native game require an iCloud-enabled signed update. A build without that capability shows “iCloud update pending” and retains local saves; it never reports cloud backup as active.

The implementation and activation boundary are documented in [Cloud saves](cloud-saves.md). Local saves stay in each game app. Never delete a game app until its needed progress has a verified backup.

## Import directly on the iPhone

1. Open reSwitch. Tap the library icon immediately to the left of Settings, or open Settings → Games & saves → Files & imports.
2. **Add game file:** choose an uncompressed `.nsp` or `.xci` from On My iPhone, Downloads, iCloud Drive, or a connected drive. The container header is checked, then the file is copied into the app for offline access. After importing, choose the game's existing profile or enter its name and base title ID to add its HOME card. Updates and DLC can be stored as separate source files associated with that game.
3. **Add prod.keys:** select the actual `prod.keys` text file. If it is in a ZIP, tap the ZIP in the iPhone Files app to extract it first. Syntax, sizes, required header key, and conflicting duplicate entries are checked. Keys are stored in the device-only Keychain, never displayed, never included in card exports, and never uploaded.
4. **Add firmware ZIP:** select an archive containing NCA files. The bounded ZIP directory check rejects traversal paths, symlinks, installers, encrypted/split/ZIP64 archives, and excessive sizes. This stores the archive; NCA decryption and integrity validation happen during preparation.
5. To add a prepared game, choose Add games → Import game cards and select its `.iswitch` file. Existing titles are updated without resetting favorites or launch history. A planning card cannot replace a prepared game.

**No Mac is needed to add or manage these files. Running a newly imported raw NSP/XCI with nxnative still requires Mac preparation.** nxnative rewrites game code and compiles shaders into a separately signed app. The launcher cannot turn an imported raw file into executable code on a stock iPhone. An Apple developer account does not remove that architecture constraint. Switching to an on-device emulator would require a different runtime and a verified JIT workflow on the user's iOS version.

A file listed as stored is not advertised as installed, decrypted, compatible, or playable. Downloading from a cloud provider may take time; keep the app open until the import finishes. Keys and imported large source files are excluded from library exports; retain your originals. Removing an imported copy leaves the original in Files and any installed game's saves untouched.

## Installation without owning a Mac

Signing/installing an already prepared IPA and preparing a raw game are separate steps. As checked on 23 October 2026:

- [SideStore](https://docs.sidestore.io/docs/installation/prerequisites) supports an initial setup on Windows, macOS, Linux, or Chromebook, followed by on-phone signing/installation over Wi-Fi. This route has not been validated with this launcher, Mario's increased-memory entitlement, or this user's iOS 27.2 beta. It does not perform nxnative's game preparation.
- A private hosted Mac could run the existing preparation tools and sign per-device builds, giving users a phone-based upload/install flow. This is a proposed architecture, not an implemented service. [Apple's ad hoc distribution](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/) requires registered devices and a distribution certificate; the developer account allows [100 iPhones per membership year](https://developer.apple.com/help/account/devices/devices-overview). A delivery service must keep game uploads, keys, signing credentials, and install links private and validate the required entitlement on each signed game.
- [TestFlight](https://developer.apple.com/testflight/) lets testers install the launcher directly on their phones and requires review for external testing. It does not by itself prepare or distribute each user's native game app.

No signing service, tester invitation, cloud upload, certificate export, or new distribution channel was created during this UI update.

## Build the launcher

Install Xcode and XcodeGen. Stage the official SDK from the owner's existing ArcStation archive, then generate the project:

```sh
cd launcher
python3 Tools/PrepareDiscord.py
xcodegen generate
open reSwitch.xcodeproj
```

The project stores the owner's development-team identifier, `HT92D8SX2K`, so Xcode and command-line builds use the same team. No signing credentials are stored in the project. On another developer's account, replace that identifier and configure a private iCloud container consistently in the launcher and native game projects. Choose the connected iPhone and reSwitch scheme, then Run. The app targets iOS 26 or later. A correctly signed app is needed to exercise Keychain storage; unsigned simulator builds may return a missing-entitlement error.

`PrepareDiscord.py --archive /path/to/DiscordSocialSdk-1.10.19337.zip` accepts another location for the same authorized archive. It verifies SHA-256 and extracts only the iOS/device and simulator XCFrameworks. Generated SDK binaries remain ignored under `launcher/Vendor/`; they are not included in source backups or Git. Third-party SDK notices are bundled in the app's Settings. Both SDK frameworks must be embedded and signed.

For terminal builds, use a derived-data directory outside a cloud-synchronized Documents folder to avoid Finder resource-fork metadata interfering with signing:

```sh
xcodebuild -project reSwitch.xcodeproj -scheme reSwitch \
  -destination 'generic/platform=iOS' -configuration Release \
  -derivedDataPath /tmp/iswitch-device-build \
  DEVELOPMENT_TEAM=YOUR_TEAM -allowProvisioningUpdates build
```

## Prepare a game app

Keep game files, keys, extracted assets, caches, and generated game projects outside this repository. Use a separate folder for each game's base XCI/NSP, updates, and DLC. The preparation tool chooses the newest update in that folder and reuses completed stages on subsequent runs.

```sh
python3 -m venv '/path/to/Games/.venv'
'/path/to/Games/.venv/bin/python' -m pip install lz4 capstone fonttools 'backports.zstd; python_version < "3.14"'
brew install xcodegen zstd spirv-cross glslang dotnet
'/path/to/Games/.venv/bin/python' scripts/iswitch.py doctor
'/path/to/Games/.venv/bin/python' scripts/iswitch.py prepare '/path/to/Games/One Game' \
  --keys '/path/to/Games/Keys/prod.keys' --xcode
```

The doctor checks the .NET 10 SDK and both Apple Metal compilers. If Metal is unavailable, install the toolchain with `xcodebuild -downloadComponent MetalToolchain`.

Alternatively, double-click `scripts/reSwitch Prepare.command`. It uses `ISWITCH_PYTHON` if set, then a venv at `~/Documents/iSwitch Games/.venv`, then system Python. Native dialogs select the game folder and keys. This wrapper passes file paths as arguments, not executable shell text.

Open the generated `NxNative.xcworkspace` and select the game's scheme and your development team. Build Release on your iPhone. Keep the Increased Memory Limit entitlement. The accompanying `.iswitch` card contains the title, version, cover, compatibility status, and a restricted per-title launch URL; it contains no game code, keys, or private source paths.

If Apple reports that the default `org.nxnative.<title-id>` identifier is unavailable, add `--bundle-id com.yourname.iswitch.mario` to preparation, using your own unique identifier. Xcode must have a signed-in developer account to register the identifier and provision the Increased Memory Limit capability. A cached wildcard signing profile alone does not provide that capability. Preserve the chosen identifier on later builds to retain the game's data.

Without `--xcode`, preparation generates an unsigned IPA. Signing and installation are separate operations. The launcher routes to directly installed game apps through `nxnative-<title-id>://launch`. LiveContainer-specific routing is not implemented.

## Optional firmware resources

```sh
python3 scripts/iswitch.py import-keys '/path/to/keys.zip' --output '/path/to/Games/Keys/prod.keys'
python3 scripts/iswitch.py firmware '/path/to/firmware.zip' \
  --keys '/path/to/Games/Keys/prod.keys' --output '/path/to/Games/Firmware/version'
python3 scripts/iswitch.py prepare '/path/to/Games/One Game' \
  --keys '/path/to/Games/Keys/prod.keys' \
  --system-data '/path/to/Games/Firmware/version/system-data' --xcode
```

The firmware helper extracts verified Data NCAs with system-data title IDs `0100000000000800` through `01000000000008ff`, records the archive SHA-256 and available IDs, and stages them into the game app. The runtime mounts a matching supplied resource when requested. It retains its existing Mii-model fallback when the relevant resource is absent. Firmware programs are not executed; importing firmware does not imply all firmware services or Mii rendering work.

## Data and recovery

Library metadata is written atomically with a previous backup. Invalid primary data is retained before recovery; if neither copy validates, the app stops writes and offers recovery export/reset. Covers are normalized to bounded JPEG thumbnails and cached with a memory limit. Import decoding and large-file operations run on dedicated actors. The file vault uses atomic metadata writes, protected local files, free-space checks, and staging files that are removed after an interrupted import. Interrupted deletions restore an indexed file or finish removing an unindexed staged file. Active file imports prevent swipe, Done-button, and controller-B dismissal.

Per-game builds now use isolated generated Xcode directories, including unsigned IPA builds, so preparing different games cannot race over the shared `dm/ios/Gen` folder. A per-folder lock prevents two preparation assistants from mutating the same game's workspace. Generated system-data resources are removed from a rebuilt app when that optional input is no longer selected.

Game saves remain in each installed game's Documents/save folder. Back up saves in Files before removing or replacing a game app. A launch callback only proves that iOS opened the app; it does not establish successful gameplay.

## Validation

```sh
swift test --package-path launcher --scratch-path /tmp/iswitch-core-tests
python3 -m unittest discover -s dm/ios/tests -p 'test_*.py'
xcodebuild -project launcher/reSwitch.xcodeproj -scheme reSwitch \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/iswitch-ios-build test
```

Core tests cover card validation, launch URL restrictions, atomic updates, corruption recovery, backup retention, duplicate handling, search/sort, keys, and game/firmware container checks. A native parser test compiles the actual Objective-C launch-link header and rejects malformed or unrelated requests. App-hosted tests exercise actual Keychain replacement and local-file ownership. UI tests cover navigation, persistence, portrait/landscape, file-picker presentation, manual cards, and the saved HUD preference. Simulator checks do not prove physical-device game compatibility or sustained performance.

`HardwareSmokeTests` is separately opt-in through `ISWITCH_HARDWARE_SMOKE=1` in the test-run environment. It exercises the preloaded Mario app on the configured physical device, checks that stored keys and firmware are visible, opens Play, and captures screenshots with the HUD off, then on and off again while resuming. It is not a full-game compatibility or performance certification.

## Preservation

The original upstream history was forked to `https://github.com/odestins/nxnative`. A full-history Git bundle is kept locally under `.git/preservation/nxnative-upstream.bundle`. Launcher changes are local on `codex/iswitch-launcher` until explicitly committed/pushed. No games, firmware, keys, IPAs, or extracted user assets belong in the source repository or its Git history.
