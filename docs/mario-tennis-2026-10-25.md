# Mario Tennis Aces bring-up — 2026-10-25

Status: **not playable; not installed on either device.** This is a new port, not
an existing supported profile. The title screen and story captions render on the
Mac, but most of the 3D scene is missing. Preparing the iOS project and translating
shaders does not establish iPhone or iPad gameplay support.

## Source and workspace

- Title: Mario Tennis Aces, base version 1.0.0 / v0, SDK 4.5.0, NVN.
- Title ID: `0100BDE00862A000`.
- Main build ID: `182c245d014cfe16b264ee0cebbc24e1`.
- SDK build ID: `e01ad5381c948c4ec3b0bb210b08d5c8`.
- Movie module: `303578054faefc2198114b62e408c498`.
- Source directory: `/Users/stanley/Downloads/Nintendo Switch/Mario Tennis Aces`.
- The original `Mario Tennis Aces ROMSNS.COM.xci` was renamed to
  `Mario Tennis Aces [0100BDE00862A000][v0].xci` so the packer's filename parser
  can identify it. The contents were not changed.
- Survey, provisional profile, extracted files, generated shader libraries, and
  prepared Xcode project are in that directory's `0100BDE00862A000_*` folders.
- Logs, isolated test saves, captures, diagnostic binaries, and launcher backups
  are in `MarioTennis-work`. No game data or keys are in this repository.

## General fixes retained

1. The rewriter recognizes a checked 32-bit jump-table index zero-extended with
   `and x18,x8,#0xffffffff`. The adjacent comparison and unsigned bounds branch
   must match; negative fixtures reject unrelated or stale checks.
2. Movie decoder C2 base constructors use the same host implementation as C1.
   Previously Tennis created a guest decoder whose layout was incompatible with
   the host's `Configure` hook, causing a null call during startup.
3. Shader extraction reads NARC allocation tables, their raw-DEFLATE entries,
   and bounded Camelot type-0x50 LZ streams. Nested particle archives previously
   hid thousands of shaders. The LZ format reference is
   [the original decompressor](https://github.com/simontime/MarioTennisAces0x50Decompressor/blob/master/decompress.c);
   this implementation adds explicit input, distance, and output-size checks.
4. NVN command recording honors `SetCommandMemoryCallbackEnabled`. A disabled
   callback must not be invoked when host command records exceed a fixed guest
   recording. The existing host overflow storage is used in that case.
5. Per-stage program binding does not restore explicitly unbound geometry or
   tessellation shaders merely because vertex and fragment stages share a program.

## Evidence and remaining failures

- Both Mac and iOS shader passes attempted 16,892 shaders: 16,770 succeeded,
  122 failed. The observed failures include SPIRV-Cross output referring to an
  undeclared `gl_BuiltIn_5253` (ViewportMaskNV). The pinned translator is unchanged.
- Using the game's own `font/nintendoP_NewRodin-EB_003.ttf` avoids the startup
  font failure observed with the larger default shared font. The prepared iOS
  resources contain this font. Mac runs set `DM_SHARED_FONT` explicitly.
- The game's 16 MiB command-record pool exhausts during the opening story.
  A diagnostic copy changes main offset `0x89a0` from `e3030832` to `0380a052`
  (16 to 64 MiB); the original instruction was verified before editing. This
  avoids that crash in bounded Mac runs but is **not** a release patch or proof
  against a longer-term leak. The normal rewritten image remains unchanged.
- The lava pipeline requests geometry plus tessellation, which the host cannot
  capture. This is a concrete unsupported pipeline, not a missing game file.
- `boot11` ran for four minutes with the diagnostic pool and full Mac shaders;
  captions and a Marina Stadium card appeared, but the scene remained black.
- `boot12` tested `tex_flush_upload` and `tex_dirty_upload`. They did not fix the
  scene; the experimental keys were removed from the provisional profile.
  Its frame-1514 pass and texture dumps show mostly empty scene attachments;
  the video conversion target retains a partially drawn image. VP9 output buffers
  are produced, but decoding alone does not prove the video reaches the screen.
- `boot13` repeats the check in docked mode with the texture-upload experiments
  removed. The story captions and illustration cards render at the expected
  larger size, but the missing scene remains. Neither mode is accepted as playable.
- Test saves are separate from the user's saves. Existing Switch library folders
  were backed up from both devices; no Tennis card or game was installed.

## Checks

- 26 Python tests passed: shader-container fixtures, jump-index fixtures, and
  shader-chain checks.
- 104 NVN checks passed, including disabling and re-enabling the memory callback.
- 105 geometry checks passed, including partial program-stage binding and the
  existing GPU replay tests.
- Mac host builds succeed. The iOS Xcode project is prepared, but signing,
  physical-device installation, and gameplay acceptance are still outstanding.

Before delivery, resolve scene rendering, the unsupported shader paths, and the
command-pool lifetime/size requirement. Then rebuild the complete iOS resources,
sign, test an actual match on each device, and merge the launcher card into freshly
backed-up libraries without replacing existing games or saves.
