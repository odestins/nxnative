# iCloud saves

reSwitch and its native game apps share the private iCloud Documents container `iCloud.com.odestins.iswitch`, plus a shared Key-Value Store preference for enabling backups. The owner’s signing team is `HT92D8SX2K`. No game packages, keys, firmware, Discord tokens, or profile photos enter this save container.

## Player behavior

- Settings → Games & saves → iCloud saves shows availability, upload status, recent checkpoints, and restore actions.
- A game captures its committed `Documents/save` directory after a successful save transaction. Existing progress is also captured on the first updated launch. Games continue with local progress while offline.
- A newer cloud checkpoint may restore before the game starts only when local progress is unchanged since its known ancestor and the game version matches. Unpublished local changes, concurrent device histories, and version differences require a choice. Dates are labels, not conflict-resolution authority.
- A manual restore is identified by a strict UUID launch parameter. If the game is already running, it prompts for a restart; a remote update never changes a mounted save tree.
- Restoring validates every file before an atomic directory swap, retaining the previous save under the game’s `Documents/Save Backups` folder. These recovery copies are deliberately retained for the owner to manage in Files.
- A build without iCloud signing shows an explicit pending-update screen. It does not make cloud API requests or claim that local progress has been uploaded.

## Implementation and limits

`cloudsave/` is a shared Swift package. A checkpoint is a single immutable `.switchsave` document with bounded JSON metadata, vector clocks, SHA-256 hashes, and streamed payloads. It preserves empty folders and the host’s guest-filename metadata. Symlinks, traversal, duplicate/colliding paths, damaged/truncated data, and wrong-title restores are rejected. Limits are 512 MB of save data, 10,000 entries, a 4 MB header, and 64 device-clock entries.

The host’s commit mutex protects a fast APFS clone; hashing, archive writing, and coordinated iCloud I/O run off the main actor. At most one active capture and the newest waiting capture are retained. An atomic persistent outbox precedes local history updates, allowing recovery after a process interruption. Identical content is not archived repeatedly. Cloud publication stages a complete file before renaming it into place. Each installation retains three confirmed uploaded revisions plus its latest pending checkpoint; cleanup never deletes another installation’s records or concurrent history.

An `NSMetadataQuery` discovers cloud documents and requests placeholder downloads. File coordination protects reads, publication, restoration, and pruning. The initial cloud lookup has a four-second wait budget; slow lookup cannot begin a late restore after gameplay starts. Actual integrity checks and an explicitly chosen restore finish before gameplay begins. Stopping the catalog cancels its pending UI work and prevents stale query callbacks from restarting it.

The current integration covers the normal `Documents/save` mount used by the owner’s four installed games. Diagnostic `DM_SAVE` overrides remain isolated and are never uploaded. Additional device-specific save mounts such as a future game’s `save_device` need an explicit multi-mount implementation; they are not silently included in the current format. No automatic cross-version save conversion is claimed.

## Signing and validation

The app target now stores its development team so Xcode’s GUI and command-line signing use the same account. Xcode registered the container and issued a profile listing it on 24 October 2026. The game entitlement merger retains Increased Memory Limit while adding the shared iCloud capabilities. All four native projects have been prepared with the integration.

Local evidence: 14 Swift tests cover integrity, atomic restore/recovery, unsafe paths, guest filenames, causal conflicts, unpublished local progress, game-version changes, interrupted journal writes, disabled sync, offline restart, bounded queued copies, and restoring an older checkpoint without rewinding revision history. The actual Objective-C URL parser passes its HUD/UUID and malformed-request checks. The entitlement merge preserves the game memory capability. The host filesystem regression suites pass 142 checks. The integrated iOS runtime compiles for arm64.

Signed-device installation is complete for Switch and all four games. Mario’s existing progress uploaded on the iPhone, and a real manual restore retained an identical recovery copy and advanced the history without changing the saved bytes. See the latest delivery entry in `validation-2026-10-23.md` for evidence. Restore on a second device and a real multi-device conflict remain unverified; local tests and a same-device restore do not establish those outcomes.

For manual command-line native builds with a separate output directory, pass `SYMROOT=<output>/Build/Products` and `OBJROOT=<output>/Build/Intermediates.noindex` together with `DM_XCODE_OUTPUT_ROOT=<output>`. Swift package products must use the same product directory as the game target. The packaging script already supplies these settings. The launcher’s `reSwitch Hardware` scheme builds Release UI checks without attempting Debug-only `@testable` unit imports.
