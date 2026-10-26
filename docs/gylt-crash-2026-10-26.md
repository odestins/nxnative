# GYLT poster cinematic crash

GYLT 1.2 (`0100AC601DCA8000`, main build
`4584432786f462dbae0e2c0bb8e0523e`) crashes on the iPhone when the cinematic
starts after Sally posts the poster. Two collected user logs and a physical
iPhone reproduction have the same null dereference at `main+0x2e45678`.

## Evidence

`FAudioDevice::GetSoundClassCurrentProperties` (`main+0x27de450`) returns null
for the loaded `VACinematics` sound class. The caller immediately reads its
volume from that pointer. The sound-property hash table is structurally valid;
the class is absent, rather than stored in the wrong bucket. The second caller
at `main+0x26d2a44` also dereferences the result without checking it.

A separate startup trace found sound classes completing `PostLoad` before
`GEngine` had its audio manager. The later `InitSoundClasses` snapshot omitted
two of those classes. Slowing startup changed which cinematic classes were
missing, so checking one class name or forcing one timing would be insufficient.
The exact reason the initial object snapshot omits those classes remains an
investigation limit; Unreal's object enumeration excludes internal loading
states. The trace itself is not a gameplay test because its breakpoints caused
a separate loading timeout.

The original crash occurred with roughly 1.2 GiB process footprint and ample
reported memory headroom. It is an audio lookup failure, with no evidence of
an iCloud save operation causing it.

## Repair

Both call sites use a build-gated AArch64 wrapper. It keeps the original lookup
for normal hits and null classes. On a non-null class miss it invokes the
game's own `RegisterSoundClass`, then retries the unmodified lookup once. The
engine registers both its static and dynamic property maps; subsequent mixer
updates and unregistration use the normal engine paths. These callers execute
on the audio thread, which is the game thread when threaded audio is disabled.
The wrapper does not fabricate properties, skip the cinematic, or disable audio.

The rewriter's `STUBS` table supports this code-only wrapper in GYLT's large
module layout (patch area before the module base). Original call bytes and the
exact NSO build ID are checked before patching. Unrecognized game builds receive
no fixed-address audio changes.

## Validation

- Patch registry checks pass.
- Unicorn executes the emitted AArch64 wrapper in both near and far layouts.
  Tests cover existing classes, null input, successful registration, and failed
  registration without recursion. They also check stack alignment, callee-saved
  registers, return values, and both call-site branch destinations.
- Signed build `1.2.1` (game version still `1.2`) installed in place on the
  iPhone 17 Pro. Signature verification passed, including the existing iCloud
  and Increased Memory Limit entitlements.
- Replayed a new game through posting the poster, the ensuing cinematic, and
  movement in the snowy area with the new objective "Take the cable car".
  The debugger observed `VACinematics` being registered at the former failure
  point. A later memory inspection found it in property-map entry 40 with its
  correct volume of approximately 0.65.
- The movie decoder completed 872 output frames. The captured run continued
  beyond 7,800 game frames with no `CRASH` or `[RED]` entries; representative
  gameplay windows were approximately 30 fps and 1.3-1.4 GiB footprint. Audio
  rendering continued, although listening quality was not assessed remotely.
- Hash comparison confirmed all four original save/configuration files were
  unchanged, and the normal save directory remained as it was before testing.
  Test progress used a separate directory excluded from cloud synchronization.
- All 16 temporary phone test files/directories were removed through the app's
  file service, followed by another original-file hash check. No persistent
  input automation or test-save override remains.

This validates the reported opening-scene failure, not a complete playthrough.
The phone run used an attached debugger with a registration-only breakpoint;
it did not use the slow startup tracing that caused the earlier loading timeout.
After gameplay validation, the process terminated during a debugger expression
attempt to remove temporary files, and the phone was locked afterward. Cleanup
was completed through AFC instead. A further normal launch was blocked by the
lock screen; this was not counted as another gameplay test.

Game files, raw logs, original Documents and Preferences backups, and diagnostic
captures remain outside the repository in the GYLT work folder's
`crash-20261026` directory. Tests use a separate save directory.
