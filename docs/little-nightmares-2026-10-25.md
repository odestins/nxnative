# Little Nightmares Complete Edition — 2026-10-25

Status: **experimental build signed and installed on both iPhone and iPad at
the owner's explicit request after the initial unsigned delivery.** Mac
opening-room testing passed. Device startup results are recorded below; this
is not a full-game compatibility certification.

## Source and outputs

Folder: `/Users/stanley/Downloads/Nintendo Switch/Little Nightmares Complete Edition`.

- Original `Little Nightmares Complete Edition (Base Game).rar` retained.
- Extracted `Little Nightmares Complete Edition [01002FC00412C000][v0].nsp`
  retained beside the archive, as requested. Extraction completed successfully.
- Update `Little Nightmares Complete Edition v1.0.4.nsp` merged; the game's
  control metadata confirms display version **1.0.4**.
- `LittleNightmares.ipa`: approximately 3.1 GB, unsigned, bundle ID
  `com.odestins.iswitch.game.01002fc00412c000`, device families 1 and 2,
  minimum iOS 26.0. iCloud save integration is included but untested for this game.
- `LittleNightmares.iswitch`: packaged/experimental launcher card with artwork.
- Survey, extraction, rewritten modules, shaders, and build logs remain in the
  `01002FC00412C000_survey` and `01002FC00412C000_build` directories.
- `LittleNightmares-work` contains isolated test saves, logs, screenshots, and
  read-only backups of both devices' launcher libraries. No device library or
  user save was changed.

The packer's `v1` folder is a fallback label for the update filename without a
numeric `[v...]` tag, not a claim about the CNMT version. Display version 1.0.4
and module build IDs identify the tested build.

## Profile and compatibility changes

Title ID: `01002FC00412C000`. Unreal Engine 4, NVN, Nintendo SDK 3.5.1.

| Module | Build ID |
| --- | --- |
| main | `bd8dcb0eaf0300e165e6d9a57fc8d024` |
| sdk | `8bb65519bc6399ab432e0ba7cdb16e2b` |
| subsdk0 (movie) | `80d47ec27d36e0fe5b5643c07d706513` |

1. Profile inference now applies Unreal's large virtual address layout only
   when the NPDM declares system resource. This game uses a conventional heap:
   its startup requests `0xc5600000` bytes. The previous all-alias layout left
   no room for that heap. The profile uses a 4 GB reservation, 256 MiB each for
   alias and stack, and the packer's measured 126 MiB rewritten-module usage.
2. Audio renderer initialization resolves the lock family after inspecting the
   SDK's update function. SDK 3.5.1 uses `nn::os::MutexType` at offset `0x1f8`
   and does not export `SdkMutexType::Lock`; resolving the latter first aborted.
3. Both SDK 3 movie decoder constructor aliases now use the host decoder.
   Their signatures have no mode or priority argument. This avoids entering
   the original NVIDIA OMX decoder on a host without nvdrv.
4. SDK 3's output-format value 3 maps to NV12 (later SDKs use 4), and its
   `GetOutputBufferSize` second output is alignment 32 rather than decoder mode.
   The distinction is attached to the old constructor, without changing later
   SDK callers. The intro then produced 361 video output frames and 574 audio
   outputs in `boot06`.
5. The game profile defaults to the full virtual controller for camera input.
   The launcher catalog was regenerated to include the new profile and existing
   fork profiles that its bundled copy had omitted.

No game-code cuts, fixed-address runtime hooks, or shader translator changes
were added. The diagnostic addresses above explain the observed SDK behavior;
runtime selection uses symbols and instruction inspection.

## Validation and limits

- Mac and iOS shader builds: **12,286/12,286 successful**, including generated
  variants. The shader chain remains `657c42552d82`.
- Mac `boot06`: intro visibly rendered, brightness setup, 3D story selection,
  and isolated save files created.
- Mac `boot08`: loaded the saved session, resumed Six's opening room, moved
  left/right with corresponding character and camera movement, and opened the
  pause menu. Four-minute bounded run; no crash or `[RED]` diagnostics. The test
  runner ended it with SIGTERM and the host shut down cleanly.
- Opening-room resident memory was approximately 3.1 GB. Several gameplay
  samples had median frame intervals near 16.7 ms on this M4 Max; these numbers
  do not predict iPhone/iPad performance. Audio callbacks reported no underruns
  in the final sampled interval; audible fidelity was not independently checked.
- The room and character appear very dark, and controller glyphs are absent
  from captured menu hints. Graphical accuracy and lighter behavior remain
  unverified. No claim is made about later chapters, DLC gameplay, multiplayer,
  device memory limits, or iCloud transfer between devices.
- `boot07` is not valid gameplay evidence: an iOS shader rebuild was temporarily
  replacing the shared Mac cache. It was stopped, and `boot08` started only
  after all libraries and their input stamp were present.
- Focused Python checks passed: memory inference, Mac build pipeline, shader
  chain, profile patches, launcher cards/project template, and cloud entitlements.
  The project-template test needs `DM_SAVE_SYNC_PACKAGE` pointing to this
  checkout's `cloudsave` package. Native audio buffer and SPSC queue tests passed.
- IPA metadata confirms the correct title, version, URL scheme, and iPhone/iPad
  families. No signing profile or code-signature resource is packaged.

The initial delivery stopped at the unsigned package under the repository's
default instructions. The owner's subsequent “sign and install” request
explicitly authorized the following delivery.

## Signed device delivery

- Installed Little Nightmares 1.0.4 on iPhone 17 Pro and iPad Pro 12.9-inch
  (6th generation, M2). Device inventories confirm the version and bundle ID.
- Apple Development signing uses team `HT92D8SX2K`. The generated profile
  includes both devices, Increased Memory Limit, and
  `iCloud.com.odestins.iswitch`; profile expiration is 2027-10-26 UTC.
- Saved `LittleNightmares-1.0.4-signed-iPhone-iPad.ipa` beside the source files.
  Strict signature verification passed. All 27,209 archived files were compared
  byte-for-byte with the signed app, and the ZIP CRC check passed. Its size and
  SHA-256 are recorded in `LittleNightmares-work/delivery/delivery.json`.
- Backed up each device's Switch library independently. The app's own
  `GameTransfer` and `LibraryRepository` implementations validated and merged
  the card and cover. Existing records were preserved: iPhone 4 → 5 games,
  iPad 1 → 2. Device readbacks match the staged libraries exactly. Only the new
  cover and library metadata were written; account data and saves were untouched.
- iPhone normal startup passed frame 2400 without a crash or `[RED]` diagnostic.
  An earlier run with `DM_NVN_SHOT` stopped advancing during capture; the
  repeated run without that diagnostic hook progressed normally. No diagnostic
  environment file was installed. The test process was terminated afterward
  and Switch reopened normally.
- The iPad initially blocked launch while locked. After the owner unlocked it,
  native rendering passed frame 3900 without a crash or `[RED]` diagnostic.
  The test process was terminated and Switch reopened normally on the iPad too.

The launcher card remains experimental. Full device gameplay, image fidelity,
later levels, and iCloud save transfer are not established by this installation.
