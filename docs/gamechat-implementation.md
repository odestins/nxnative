# Chat implementation and launcher review

Authorized by the owner on 23 October 2026. Source reference: the existing ArcStation Discord service and Objective-C++ bridge. ArcStation remains unchanged.

## Acceptance criteria

- [x] Reuse Discord application `1560449870496792729` and the pinned official Social SDK 1.10.19337, including native iOS and simulator libraries. The owner confirmed the mobile callback; no app ID or client secret entry in reSwitch.
- [x] Implement native account linking with PKCE, phone Keychain storage, restoration, refresh, cancellation, reconnect, and local disconnect. Do not copy ArcStation's rotating refresh token between devices.
- [x] GameChat-style Create Chat / Chat List interface, Discord friends, private conversations, party text, incoming/outgoing invitations, participant tiles, voice join/leave, mute/deafen, speaker routing, and per-person volume/mute.
- [x] Implement background audio, interruption handling, and game audio coexistence. Live two-person/background audio acceptance remains pending below.
- [x] Bound message history and event refreshes, cancel stale work, preserve drafts after failed sends, and avoid publishing unchanged SDK snapshots. No placeholder friends in normal use.
- [x] Review launcher/import/storage/controller/runtime boundaries, fix concrete bugs, and test recovery and UI layouts.
- [x] Run core, app-hosted, UI, bridge, packaging, and signed-build checks. Install without removing user data. Record live authentication, messaging, and two-person voice acceptance separately from fixture tests.

## Scope and evidence boundaries

This implements Discord Social SDK friends, DMs, and lobby text/voice using the same application as ArcStation. The SDK does not expose a full Discord server browser or arbitrary Discord voice channels. Screen sharing and video are outside this text/voice request. The interface follows Nintendo's GameChat arrangement with reSwitch's established red action tint and original navigation colors.

Live messages and invitations are sent only by the user's explicit action. Build checks and simulated transports do not establish two-person voice quality. A compatible second SDK client and confirmed communications access are needed for that check.

## Review findings

- Changed native game audio from SoloAmbient to mixable Ambient while retaining the silent-switch behavior. Rebuilt and installed Mario; startup/HUD checks passed.
- Separated Discord/invitation callbacks from file imports. Only file URLs enter the importer. Incoming links do not interrupt an active file import or automatically activate voice.
- Added bounded request deadlines and generation checks so stale message, refresh, microphone, and call callbacks cannot restore a disconnected session or replace the selected chat.
- Converted Objective-C callback payloads to immutable bytes across Swift 6 executor boundaries. The SDK remains main-actor driven; its callback pump starts lazily and pauses in the background without voice.
- Canceling sign-in clears this device's pending credentials. Local disconnect leaves the party and clears the phone's credentials without revoking ArcStation's application grant. A late canceled token response is discarded instead of revoking the shared grant.
- Audio route changes and interruptions update controls. The speaker switch updates both the category default and explicit route override, so turning it off can return to the receiver/headphones. Mute remains available while a voice session is active during gateway reconnection; failed calls can be rejoined.
- Protected imports from sheet/controller dismissal. Source-file deletion stages a reversible rename before committing the index; launch recovery restores or cleans interrupted deletions. Malformed/duplicate source references fail closed.
- Prevented duplicate library loading. Restored Done controls on nested chat screens and preserved alert presentation during navigation and keyboard input.
- Kept recent message lists bounded, coalesced message events, compared snapshots before publishing, and retained per-conversation drafts after failed delivery. No synthetic friends/messages appear in Release.

## Validation

17 core tests, 17 Python packaging tests, 13 app-hosted tests, and eight simulator UI tests passed across the final focused runs. App tests include real bridge/config availability plus simulated network/lifecycle failure cases. UI fixtures are explicitly selected and excluded from Release.

Signed Release builds for Switch 1.0.0 (7) and Mario passed, including framework signature verification and Mario's Increased Memory Limit entitlement. The physical iPhone check passed for preserved keys/firmware, profile controls, Mario startup/rendering, warm HUD off/on/off changes, and the GameChat account screen. The final Release copy is installed. All eight committed/working save files matched the backup after Mario installation.

The owner authorized the real Discord account and confirmed friends appeared. A physical iPhone test then relaunched Switch and verified that the official SDK restored the account and reached Ready without another sign-in. On the final Release build, the owner created a private chat, allowed microphone access, and reported voice status **Connected**. This is owner-confirmed single-client connection evidence; it does not prove two-way audio. Sending a real DM, accepting a real invitation, two-person voice quality, Bluetooth routing, and background voice during gameplay remain live acceptance checks, not conclusions from the fixtures. Discord's separate mobile invite-launch portal setting is unverified; shared-code and in-app invitation paths are implemented.

See [delivery validation](validation-2026-10-23.md) for the retained artifacts and exact preservation checks. ArcStation itself is unchanged.

## Build 9 interface and efficiency update

The user-facing feature is now **Chat**. The dashboard puts friends and previews immediately below Start Chat, with a direct return card for an existing party. Connection settings are in the account row. Voice controls use a compact header, including a single row in landscape; participants, invitations, per-person mute/volume, and share code are in People & invites. Invitation buttons are visible and suppress repeated requests. Nested screens retain Done without duplicating it on the dashboard.

The composer follows the keyboard, retains failed messages, and presents delivery failures inline. Reading position is preserved for incoming messages while browsing history; resizing follows the conversation's bottom. Twenty conversations can cache up to 100 recent messages each. The SDK callback pump uses 2 Hz on idle HOME, 10 Hz while viewing/linking, and 20 Hz during voice; these are timer settings, not measured battery-life claims. Local mute remains available during a gateway reconnect. Blocking/disconnecting clears the applicable cached history. Invitation completions are scoped to their originating party.

The full simulator run passed 14 app-hosted tests and eight UI tests before the final voice-reconnect regression was added. The layout refinement subsequently passed all three Chat UI tests with visual review of portrait, landscape, and keyboard states. The final focused service run passed all 10 service tests, including the additional reconnect regression. No real messages, invitations, or calls are sent by these tests.

## Build 11 readability update

The button beside Start Chat now reads **Join** and opens the existing invitation-code prompt. It uses a readable neutral label, remains disabled while disconnected or busy, and stacks below Start Chat at accessibility text sizes. Settings and Done controls use primary text instead of small logo-red text. Invitation, account and voice behavior are unchanged.

## Build 12 guest access — 25 October 2026

Continue as Guest is the primary onboarding action; Connect Discord remains optional. Both retain the minimum-age gate. Guests use the same party text/voice and Join controls with their reSwitch display name. Empty friend lists guide guests to invitation codes instead of requiring Discord friends. Guest identities live in a separate device-only Keychain item; transient access tokens remain in memory. Disconnecting keeps the private identity and does not silently reconnect an older Discord account.

The deployed Cloudflare broker uses the same application ID and an owner-generated bot token stored only as a Worker secret. The owner reset the bot credential after source inspection established that ArcStation uses OAuth tokens, not this bot credential. No ArcStation files, OAuth redirects, scopes or saved user tokens were changed. Temporary local setup secrets were removed after server configuration.

Optional linking uses the SDK's GetTokenFromProvisionalMerge with DiscordBotIssuedAccessToken and PKCE. Linking is disabled during an active party. Cancelling before exchange preserves the guest session; cancellation cannot discard a successful merge result while Swift saves it. A merge fingerprint in the OAuth Keychain record recovers an interrupted guest-marker update. Credential-save failures retain the current refresh token in memory, explain the limitation and retry. Existing OAuth records without the new optional marker still decode.

Renewal updates the SDK token in place without restarting an active voice connection. Temporary renewal failures preserve the call and retry. An unavailable guest record does not prevent restoration of an existing Discord account, and an unreadable old OAuth record does not block a valid guest.

Validation and unsigned artifacts: [25 October report](upstream-2026-10-25.md). The real deployed endpoint and iOS SDK guest connection, renewal and same-account restoration passed. Guest text/voice interactions passed simulated-transport UI/service tests; no real messages or invitations were sent. Two-person guest voice, live account merging and physical-phone behavior remain separate acceptance checks.
