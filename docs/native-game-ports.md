# Native game ports — 2026-10-23

The three installed ports and retained Hellblade source profile target the exact
builds below. They prepare separate, signed native
iPhone apps; Switch opens those apps through their title-specific URL schemes.
Adding a library card alone does not install executable game code. Game packages,
keys, firmware, generated shaders, signing material, and saves stay outside Git.

## Validation

Device: iPhone 17 Pro, iOS 27.2 developer beta. Measurements below describe bounded
opening-scene checks, not a complete playthrough or certification of every level.
Inputs were exercised through the host controller path; extended physical touch
and controller testing remains useful.

| Game | Title ID | Version | Observed result |
| --- | --- | --- | --- |
| GYLT | `0100AC601DCA8000` | 1.2 / v131072 | iPhone build 1.2.1 fixes missing cinematic sound-class registration. Poster scene, following cinematic, and movement toward the cable car verified on the phone; approximately 30 fps in sampled gameplay windows. [Crash investigation and limits](gylt-crash-2026-10-26.md). |
| Alan Wake Remastered | `0100623017A58000` | 1.0.1 / v65536 | Signed app installed; camera and movement advanced the opening tutorial to the lighthouse objective on the phone. Switch card linked. Opening check approximately 30 fps and 3.2 GiB footprint. |
| HOT WHEELS UNLEASHED 2 — Turbocharged | `01001BE01908C000` | 1.0.1 / v65536 | Signed app installed; a race and acceleration verified on the phone. Switch card linked. Sampled race intervals approximately 30 fps and 3.2 GiB footprint; sampled audio callbacks had no underruns. |
| Hellblade: Senua's Sacrifice | `010044500CF8E000` | 1.1.0 / v65536 | Removed at the user's request. App and library card removed from the phone; generated Mac builds, extracted files, duplicate packages and diagnostics deleted. Original Downloads packages retained. No phone gameplay acceptance. |

Mario's installed application and saves were retained. Diagnostic runs use separate
save directories. Before delivery, remove automated input and screenshot overrides
from each game's Documents/env.txt; the normal entry contains `DM_LAUNCHER=0`.
The installed ports expose both sticks, the D-pad, triggers, and stick clicks.
Hellblade's small source profile remains for reproducibility, but is not installed.
Its last Mac check rendered the opening 3D scene after enabling CPU texture-write
tracking; phone verification was cancelled when removal was requested.

Nintendo online services are not implemented by this host. Hot Wheels can display
connection warnings: acknowledge the error and choose Cancel to continue offline.
This is separate from Switch's Discord-based Chat integration.

## Runtime fixes

- Shader extraction recognizes Alan Wake RFX9 containers, modern Unreal inline
  shader records, bounded LZ4/zlib payloads, and NVN shaders embedded in executables.
- Sparse texture tile information matches the NVN four-integer ABI and 64 KiB tile
  geometry. Virtual pools retain independent, owned backing maps.
- Shader reflection accepts up to the existing 192 argument bindings. GYLT uses
  materials above the previous 64-binding limit; rejecting them made its character
  render black. Overflow remains rejected.
- Exact SDK build IDs gate memory-bookkeeping reductions. GYLT also has an exact
  executable-build allocator replacement and a bounded virtual-address reservation.
  The liveness check accepts a return boundary only when the scratch register is
  not read on that path.
- Audio renderer state, queues, resampling history, and threads belong to individual
  renderers. Nested opens initialize once. Destroying an SDK notification event
  detaches it under the render thread's event lock before the original destructor
  runs, avoiding Hellblade's stale stack-event crash.
- The host reports that no external NVN debugger is attached.
- Hellblade's manual shader facts type only output 5 as unsigned integer for 9,488
  shaders whose writes are integer bit patterns. This preserves the other floating
  outputs in its mixed G-buffer. Three unproven candidates remain unchanged.
- App staging removes Finder resource-fork metadata from the staged bundle only,
  preventing codesign rejection without changing the source assets.

Generated shader tables and libraries must share a compiler fingerprint. The pinned
translator remains unchanged. The legacy phrase “provisional profile” in some
`shader_note` values is retained because it participates in cache inputs; the
validation table above is the status authority.

## Checks

- 44 Python tool tests passed, including shader formats, patch registry, and rewrite
  liveness cases.
- 170 texture checks passed, including sparse tile geometry.
- Reflection regression accepted an 84-binding fixture and rejected overflow.
- Three staging checks passed, including extended-attribute removal.
- Signed iPhone builds completed for all four titles. Gameplay acceptance is tracked
  separately in the table above.

For the three retained ports, local build logs, screenshots, prepared projects, and source-package provenance are
under `/Users/stanley/Documents/iSwitch Games/<game>/`. Launcher/library backups
are under `/Users/stanley/Documents/iSwitch Backups/2026-10-23/`.
