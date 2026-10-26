# Switch delivery validation — 23 October 2026

## Mario map-loading freeze — 2026-10-24

The reported freeze after character selection was traced to the graphics upload allocator. The phone's `DmIOS-2026-10-24-165924.ips` shows the submission thread waiting in `up_wait_zero` from `up_begin`, while `dm-encode` sleeps waiting for published work. Three upload allocators were busy, but their GPU commits were still in a partial deferred record block. The next upload waited for completion without publishing that block. Backgrounding the already-frozen app then blocked `dm_gfx_suspend` on the main thread, causing iOS's 10-second watchdog (`0x8BADF00D`) to terminate it. This crash is not an iCloud-save operation or an out-of-memory termination.

`up_begin` now drains pending encoder records before waiting for a busy upload slot. This is a general renderer correction; parallel encoding and cloud saves remain enabled. The new `t_upload_slots` test reproduces the deadlock without game assets, saves, or cloud code, exercises twelve batches through three reusable slots, and checks the actual GPU output. Before the fix it hits its 10-second deadlock watchdog; afterward it passes under Metal validation with both deferred and inline encoding. The 102 core NVN checks pass. The separate existing `t_defer_chain` test aborts on overlapping render attachments under this Mac's Metal validation; an isolated build with this fix removed produces the identical failure. That unrelated test is not claimed as passing.

Mario 1.0.1 runtime build 2 is installed in place as signed Release. Its signature, existing app identifier, increased-memory entitlement, and shared iCloud container are verified. On the physical iPhone 17 Pro/iOS 27.2, an isolated copy of the existing save passed character selection, world-map loading, map travel, entry into “Welcome to the Flower Kingdom,” and character movement. Two background/resume cycles drained graphics successfully; the explicit app-switch check resumed the same process (PID 14854) and preserved its in-level position. A separate cold launch with the normal save path and iCloud enabled again passed character selection and loaded the world map; its log confirms the cloud checkpoint was queued and the normal transactional save mounted. The original twelve committed/working/recovery save files remained byte-identical after both runs, and every preexisting preference value was retained (13 preservation checks). These checks cover the reported freeze and the exercised level; they do not certify every level or an extended playthrough.

Full save, preference, and sync-metadata backups, the previous and updated signed apps, crash logs, before/after test evidence, and physical screenshots are retained outside the repository at `~/Documents/iSwitch Backups/2026-10-24/Mario-freeze-investigation`. The renderer and regression changes remain uncommitted on the existing branch; no other installed game app was rebuilt by this fix. All temporary diagnostic environment/input files, screenshots, and isolated save folders were removed through explicit per-file CoreDevice operations; no container-wide cleanup was used. The twelve original save files and existing preferences were checked again after cleanup. Normal launch has no diagnostic overrides.

## Build 11: Settings readability and Chat Join — 24 October 2026

Settings now uses semantic primary labels and neutral icons, with red retained for switches and brand accents. Profile controls are directly available; gameplay, games/saves, appearance and help have separate groups. Export, preview and recovery moved into Manage library; version and licenses moved into About Switch. Imported files and profile/help pages retain a Back path to Settings. Appearance changes update the open sheet immediately. Accessibility text sizes use full-width setting labels and a separate HUD switch. Chat has a visible **Join** button next to Start Chat, with a vertical layout at accessibility text sizes.

Four simulator UI checks passed for Settings navigation, file-picker presentation through Settings, appearance selection, HUD persistence, larger text, and the existing fixture-based Chat conversation/party flow. Screenshots were inspected in Dark and Light mode and both orientations. A subsequent accessibility-row refinement passed its focused check. The signed Release build and signature verification passed, including the existing team and iCloud container.

Build 11 is installed in place; device inventory confirms Switch 1.0.0 (11). After the owner unlocked the phone, the physical iPhone 17 Pro/iOS 27.2 check passed: Settings and Chat settings opened with readable labels, the dashboard displayed Join, the authorized Discord account restored without another sign-in, and iCloud reported Saves are in iCloud. Physical screenshots were inspected. All nine launcher library/artwork/photo/source-index/import files matched their pre-update SHA-256 hashes, and all existing preference values were retained. No real Chat messages, invitations or calls were initiated, and no game app was updated by this UI-only delivery.

Evidence: `/tmp/switch-build11-settings-final.xcresult`, `/tmp/switch-build11-settings-accessibility.xcresult`, `/tmp/switch-build11-device-delivery.log`, `/tmp/switch-build11-hardware.xcresult`, and the external `build11-launcher-preservation.json`. Source, signed IPA and validation evidence are retained outside the repository in `~/Documents/iSwitch Backups/2026-10-24`.

## Build 10: active Chat spacing — 24 October 2026

HOME now groups the navigation capsule and active Chat bar with a 14-point gap in portrait and an 8-point gap in landscape. The gap exists only while in a party. In landscape, game cards become more compact while Chat is active so the bottom controls remain visible. Portrait game-card sizing, navigation icons/colors, and Liquid Glass are unchanged.

The existing simulated Chat flow passed with messages, party controls, mute, and both orientations. HOME screenshots with an active party were inspected in portrait and landscape, including the bottom controls. The signed Release build and signature verification passed. No real messages, invitations, or voice sessions were initiated by this check.

Build 10 was installed in place and launched on the iPhone. All nine library/artwork/photo/source-index files matched the pre-update backup, and existing preference values were retained. The game apps and save data were not modified by this UI-only delivery.

Evidence: `/tmp/switch-build10-chat-gap-final.xcresult`, `/tmp/switch-build10-device.log`, and `build10-launcher-preservation.json` in the external backup folder.

## Build 9: iCloud saves and Chat review — 24 October 2026

Switch's development team is now persisted in the project. Xcode registered `iCloud.com.odestins.iswitch` and Apple issued matching profiles for the launcher and four native game apps. Command-line signing earlier reported “No Accounts” while the GUI displayed an account; refreshing the sign-in resolved that error. This does not establish the underlying Xcode defect. The later empty container list was a separate capability-registration issue, resolved directly in Xcode. No recurring sign-out is part of the build workflow.

The save integration snapshots committed progress, queues offline backups, checks content integrity, and resolves concurrent histories before game startup. Existing save data is captured on first upgraded launch. Restore keeps a local recovery copy, rejects malformed/wrong-title archives, and never replaces a save mounted by a running game. Settings exposes availability, upload state, recent checkpoints, and manual restore. Game packages, firmware, keys, and Discord credentials are outside the private save container.

GameChat is now labeled **Chat**. Friends and conversation previews are directly accessible; voice controls occupy a compact header with a single row in landscape. Invitation state is visible, duplicate invitations are suppressed, failed sends retain their drafts, the composer follows the keyboard, and nested screens have Done controls. Message caches and callback polling are bounded. Local mute continues to work during gateway reconnect. The original dock colors and Liquid Glass remain.

Completed checks:

- 14 cloud-save package tests, 17 launcher-core tests, Objective-C URL parser checks, the entitlement-merger regression, and 142 host-filesystem checks passed.
- The full signed simulator run passed 14 app-hosted tests and eight UI tests. The final layout refinement passed three Chat UI tests, and the final service run passed 10 tests. Portrait, landscape, keyboard, and failed-send screenshots were inspected.
- Signed Release builds passed for Switch 1.0.0 (9), Mario 1.0.1, GYLT 1.2, Alan Wake 1.0.1, and Hot Wheels Unleashed 2 1.0.1. All signatures and shared iCloud-container entitlements verified; all four game apps retain Increased Memory Limit. The dedicated hardware scheme runs UI checks against Release without enabling test-only imports in the shipping app.
- Switch build 9 and updated Mario were installed in place. Mario's first real checkpoint contained four files whose payloads and SHA-256 hashes exactly matched the existing saved progress. The physical iPhone test confirmed iCloud availability and **Saves are in iCloud**, including the uploaded marker on Mario's checkpoint. The same test confirmed that Discord restored the owner's authorized account without another sign-in. Physical screenshots were inspected.
- Nine launcher library/artwork/photo/source-index files were byte-identical after installation, and all existing preference values were retained. Mario's eight committed/working save files and its preferences were also byte-identical. Backups are under `~/Documents/iSwitch Backups/2026-10-23/pre-build9-Library`, `pre-cloud-game-saves`, and the corresponding post-update folders.

All four native game updates are now installed in place. All 12 baseline save/preference files matched their original hashes after installation. GYLT, Alan Wake, and Hot Wheels had no normal save files yet; their diagnostic save folders remain separate and are never uploaded. Hot Wheels has no unused normal `save.work` folder, confirmed by a device directory listing after a copy attempt reported it absent. The physical restore check then opened the verified Mario checkpoint through its strict launch URL and confirmed the restore in the game. All four restored files and all four retained recovery files matched the original progress by SHA-256. The causal history advanced from revision 1 to revision 2 without changing content. A follow-up physical check confirmed that the resulting checkpoint also finished uploading and Discord remained connected. This checks restoration before gameplay, not a new gameplay session. Actual upload on this iPhone is verified; restoring onto a second device and multi-device conflict interaction remain separate checks. No real Discord messages, invitations, or calls were sent during this review, and two-person voice quality remains unverified.

Evidence: `/tmp/switch-cloudsave-tests.log`, `/tmp/switch-launcher-core-tests.log`, `/tmp/switch-save-host-tests.log`, `/tmp/switch-build9-final-tests.xcresult`, `/tmp/switch-build9-landscape-tests.xcresult`, `/tmp/switch-build9-service-tests.xcresult`, `/tmp/switch-build9-cloud-hardware.xcresult`, `/tmp/switch-build9-restore-hardware.xcresult`, `/tmp/switch-build9-postrestore-cloud-hardware.xcresult`, and `/tmp/switch-build9-native-installation.log`. Source and signed-launcher snapshots are kept outside the repository; private screenshots and game-save backups are separate from the source archive.

## Build 7: Discord GameChat and reliability review

Switch reuses ArcStation's public Discord application ID and official Social SDK 1.10.19337. The mobile callback was confirmed by the owner. Native PKCE authorization, device-only Keychain credentials, refresh/reconnect/cancel, and local disconnect are implemented. ArcStation was inspected without modifications; its Mac tokens were not exported or copied.

The GameChat interface includes Create Chat, Chat List, friends/search, direct and party messages, incoming/outgoing invitations, join codes, participant/speaking tiles, microphone/deafen/speaker controls, per-person audio controls, and a HOME microphone bar. Fixture participants are confined to explicit Debug UI-test launches. The original dock colors and logo-red action tint remain.

Review fixes include nested Done controls and alert presentation, failed-send draft retention, stale callback rejection, bounded history/coalesced updates, permission/leave-party races, import dismissal protection, source deletion recovery, stricter source-index validation, and duplicate-load protection. Mario and future native builds use mixable Ambient audio to coexist with background voice.

Checks completed:

- 17 Swift core tests, 17 Python packaging tests, 13 app-hosted tests, and eight simulator UI tests passed across final focused runs. App-hosted tests include real SDK bridge/config checks and controlled failure simulations; UI tests include portraits, landscape, text entry, failed delivery, and existing import/photo/HUD flows.
- Signed Release builds succeeded for Switch 1.0.0 (7) and the updated native Mario. Both code signatures verified, both Discord frameworks are embedded/signed, and Mario retains Increased Memory Limit.
- The physical iPhone 17 Pro/iOS 27.2 check passed: original keys/firmware/profile controls visible, Mario launched and rendered for 30 seconds, HUD warm-resume off/on/off controls worked, and GameChat's connection screen opened. These checks do not establish sustained gameplay or real voice transport quality.
- Six launcher data files and eight committed/working Mario save files were backed up before installation. All eight save files matched by SHA-256 after the native install. All six launcher preservation checks passed afterward: artwork, photo, and source index were identical; library metadata changed only in expected launch history; prior user preferences remained.
- The canonical signed Release launcher and updated Mario app are installed. No app was removed, and no container cleanup/reset was performed.

The owner completed real Discord authorization on the iPhone and reported friends appearing. The opt-in physical account test then relaunched the app and verified restored authentication and the SDK's Ready state without another authorization prompt. No token was read out or exported. After the final Release installation, the owner created a chat, granted microphone access, and confirmed that the voice status displayed **Connected**. This confirms the owner's single-client connection check, not a two-person audio exchange. Real DM delivery, real invitations, two-person voice, Bluetooth, and background voice during gameplay remain unverified. The SDK requires a compatible second client and application communications access. This integration does not browse arbitrary Discord servers or provide Nintendo online services. The separate mobile invite-launch setting in Discord's portal is unverified; code sharing and in-app invitations are implemented.

Evidence: `/tmp/switch-gamechat-core-final.log`, `/tmp/switch-gamechat-python-r2.log`, `/tmp/switch-gamechat-tests-r5.xcresult`, `/tmp/switch-gamechat-final-tests.xcresult`, `/tmp/switch-gamechat-release-delivery.log`, `/tmp/switch-gamechat-mario-build.log`, `/tmp/switch-gamechat-hardware.xcresult`, `/tmp/switch-gamechat-auth-hardware.xcresult`, and `/tmp/switch-gamechat-release-auth.xcresult`. The last account check also passed with the canonical Release app selected as the UI test target. Simulator and physical screenshots were inspected. Physical screenshots and account data are excluded from the source snapshot.

## Build 6: portrait layout and Performance HUD

Portrait card width changed from 70% to 54% of the available width (about 23% smaller on iPhone 17 Pro). Portrait navigation uses five controls with icons up to 64 points and a taller capsule, replacing the previous 37-point icon layout. Album and its unused view were removed; avatar photo selection remains. The action tint, selected-card outline, and avatar fallback use the supplied logo's sRGB red `#E60012`. Following the user's clarification, the navigation icons retain their original orange, coral-red, and gray colors.

Settings → Gameplay → Performance HUD controls both the FPS counter and Metal's timing/memory overlay. It defaults to off, persists locally, and is sent through a restricted Boolean launch parameter when opening or resuming a game. The native app saves the setting for direct launches and removes the FPS timer while hidden. Mario's native app was rebuilt with this integration and installed using its existing identifier and Increased Memory Limit entitlement.

Build 6 checks:

- All 14 Swift core tests passed, including restricted HUD launch requests.
- The native Objective-C parser test passed with valid and malformed URL cases.
- Two focused simulator UI tests passed for portrait/landscape and HUD preference persistence. Screenshots of Settings and both home layouts were inspected.
- Signed Release launcher and native Mario builds succeeded. The launcher signature verified.
- All four Mario save files were backed up before the native update and matched afterward by SHA-256.
- After installing the launcher, artwork, profile photo, and source index were byte-identical to their backups. Library content was unchanged apart from expected launch history, and existing user preferences were retained. Stored keys and firmware remained visible on the physical phone.
- The physical iPhone test passed: cold launch with both overlays hidden, then warm resumes with both visible and both hidden again. Screenshots were inspected and native logs confirmed off → on → off. The game stayed running through both setting changes. An earlier automated tap was interrupted by device rotation; the test now waits for the landscape layout to settle before tapping Start.

At that delivery the installed launcher was signed Release 1.0.0 (6), and the final HUD setting was off. These checks cover startup, settings, and resuming the running title screen; they do not certify full gameplay or sustained performance.

The earlier build 4 visual update also passed orientation and profile-photo-picker tests, with the launcher library, artwork, profile photo, source index, and user preferences verified after installation.

## Earlier build 3 delivery

- Native SwiftUI launcher for iPhone/iPad, installed as **Switch** with the user's supplied icon. The existing bundle identifier and storage format remain unchanged.
- Six HOME controls: GameChat (future Discord client), Store (the requested ROMSNS URL), Album, Controllers, Game Cards, and Settings.
- Local profile photo selection, change, and removal. Images are downsampled to at most 512 pixels and 256 KB; re-encoding removes original image metadata.
- Phone Files imports for game sources, production keys, and firmware archives; manual and prepared game cards. New raw games still need nxnative's Mac preparation to run.
- A separately signed Super Mario Bros. Wonder 1.0.1 app, built from the supplied base XCI and update NSP, with the Increased Memory Limit entitlement and per-title launcher URL.

## Earlier build 3 checks

- Swift package: 13 core tests passed, covering library persistence/recovery, bounded card imports, launch links, keys, and container validation.
- Python packaging/import tooling: 16 tests passed, including system-data staging and cleanup, independent generated projects, manifests, and prerequisite detection.
- App-hosted tests: three source-vault tests and one photo test passed. Photo coverage includes downsampling, disk persistence, invalid replacement, removal, and preserving the original file.
- Simulator UI: library planning/persistence, manual cards, native Files pickers, portrait/landscape, and native Photos picker presentation passed.
- Signed Release launcher build: successful, version 1.0.0 (3). Icon and Info.plist inspected.
- Physical iPhone 17 Pro, iOS 27.2: launcher → Mario → Play passed. The game reached its user-selection screen and stayed foreground for 30 seconds. A separate run produced more than a minute of frames and active audio without an observed crash. These are startup checks, not full gameplay or sustained-performance certification.
- Physical Keychain: 231 stored key entries visible. Firmware 22.1.0 contains 238 NCA entries; the stored archive was validated and indexed. The native game includes 38 optional system-data archives. The Mii-model archive was absent, so full Mii rendering is not claimed.

The supplied Mario 1.0.1 build needed the existing resource-heap slack adjustment mapped to its own NSO build ID. Function mapping and disassembly confirmed the instruction and target before adding the build-specific patch. This version remains marked experimental.

## Recovery and limits

During delivery, a device-tool directory cleanup unexpectedly cleared the launcher's local container. The prepared Mario card/artwork and firmware were restored from retained Mac copies. Keys stayed in Keychain; Mario's app and saves use a separate container. The launcher display name preference reset. Do not use `devicectl copy to --remove-existing-content` for selective cleanup of this app's container; use app-owned file removal instead. No cleanup command should target the entire container.

Nintendo network services are not implemented. Build 7 adds the Discord Social SDK integration described above. Firmware import stores an archive and supplies selected resources during Mac preparation; it is not installation of a Switch operating system. LiveContainer routing and on-device compilation are not implemented.

## Preservation

The upstream fork is `https://github.com/odestins/nxnative`. The complete upstream history is also retained in a verified Git bundle. The source changes remain local on `codex/iswitch-launcher`; no commit or push was made. A source-only snapshot and restoration instructions are retained outside the checkout in `~/Documents/iSwitch Backups/2026-10-23/`. Games, keys, firmware, generated game binaries, and private screenshots are excluded from that source snapshot.

Build 7 adds `Switch-source-1.0.0-build7.tar.gz`, `Switch-1.0.0-build7.ipa`, `RESTORE-build7.txt`, `SHA256SUMS-build7.txt`, and `Validation-build7/` in the same backup folder. The official SDK archive remains in the owner's ArcStation Vendor/downloads directory and is restaged by the pinned verification script. The signed IPA contains the runtime frameworks; the source snapshot does not redistribute SDK binaries. Local device-data backups remain separately under the Mario workspace, outside Git and the source archive.
