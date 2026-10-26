# reSwitch multiplayer roadmap

Updated 24 October 2026.

Three planned capabilities will let friends play together through reSwitch. The initial game target is the existing Super Mario Bros. Wonder 1.0.1 port; additional games need their own compatibility checks. These items are roadmap work, separate from the installed app's existing text and voice Chat.

| Idea | Player experience | Where the game runs | Status |
| --- | --- | --- | --- |
| 1. Local co-op | Several people play together using controllers connected to one iPhone. | One iPhone runs and displays the game. | Planned |
| 2. Remote play through Chat | Friends join a host's game from their own phones and control separate characters. | The host runs the game; guests receive video and send controller inputs. | Planned prototype |
| 3. Multiplayer with each phone running the game | Each person launches their own game and plays in the same synchronized session. | Every participating phone runs and renders its own native game app. | Planned feasibility research and implementation |

## 1 Local co-op on one iPhone

Assign each connected controller to a separate player, beginning with two players and expanding to the game's supported player count. Reuse the controller-slot logic already present in the Mac front end and shared runtime. The current iOS input path sends every physical controller into player 1.

Planned work:

- Port stable player assignment to iOS, including disconnects, reconnections, and releasing held buttons when a controller disappears.
- Make touch controls and physical-controller ownership clear, and respect each game's supported controller types and player count.
- Verify character selection, independent movement, shared course progression, and save ownership in Wonder.

Initial acceptance: two real controllers independently control two characters on one iPhone through a complete course. Expand to four players only after that configuration passes its own device check.

Starting points: [iOS controller input](../dm/ios/Sources/DmGamepad.m), [Mac controller assignment](../dm/host/front_mac.m), [player slots](../dm/host/pad_slots.h), and [shared input support](../dm/host/hle_hid.c).

## 2 Remote play through Chat

One iPhone hosts the native game. Friends join through Chat, see the host's streamed gameplay, and send inputs for their assigned characters. Discord supplies the social session; a separate streaming and input connection carries gameplay.

Planned work:

- Add a Play Together flow with host, invite, join, player assignment, connection status, and leave controls.
- Capture the game's picture and audio inside its native app, evaluate hardware video encoding and a low-latency transport, and render the stream on guest phones.
- Keep voice chat usable alongside game audio. Handle guest disconnects, reconnects, backgrounding, and lost controller packets without leaving buttons held.
- Keep the host's progress authoritative and explain who owns the session's save.

Initial acceptance: a host and guest on two real iPhones complete a Wonder course together. Test both local Wi-Fi and different internet connections, recording input latency, frame delivery, audio behavior, battery use, and thermal behavior before setting supported performance targets.

## 3 Multiplayer with each phone running the game

Each participant has reSwitch and a compatible prepared game installed on their own iPhone. Both phones run their own game code and render their own view while exchanging the information needed to play together in one shared session. This is a separate deliverable from remote play; a streaming prototype does not complete it.

Planned work:

- Investigate the game's multiplayer protocols and runtime hooks. The current [network implementation](../dm/host/hle_net.c) reports the network as unavailable, so joining a Discord lobby alone cannot connect game instances.
- Evaluate adapting the game's existing network behavior versus synchronizing its local co-op execution. Prove the necessary protocol hooks or deterministic execution before choosing an approach; investigate state snapshots and rollback if the selected design requires them.
- Check compatible game versions, updates, DLC, runtime builds, and starting session state before joining. Both players keep their own game files and keys on their devices.
- Build gameplay transport, session authority, input or state synchronization, latency handling, desynchronization detection, and recovery. Start with two phones on the same network, then address internet connectivity and relay requirements.
- Define each player's progress and save ownership explicitly. Preserve personal saves and integrate session outcomes with the existing iCloud conflict protections.
- Add a per-game compatibility record so support is claimed only for versions and multiplayer configurations actually verified.

Initial acceptance: two physical iPhones, each running its own native Wonder process, independently control players in the same synchronized course. Both see the effects of both players' actions. Verify course transitions, a sustained session, packet delay/loss, disconnect recovery, and save preservation. Then repeat across different internet connections. Feasibility and performance remain open until that prototype succeeds.

## Shared Discord experience and delivery order

Reuse the existing Discord application ID and phone account authorization for friends, invitations, lobby membership, text, and voice. Bind gameplay invitations to the selected game, compatible build, and authorized participant. The existing [Chat integration](gamechat-implementation.md) remains the entry point for both remote modes; gameplay synchronization needs its own runtime work. Nintendo's official online-service interoperability is outside these three milestones.

Start with local controller support. Use it as the foundation for the remote-play prototype and begin the independent-game multiplayer investigation early. Track ideas 2 and 3 separately, with the third remaining a first-class roadmap goal even if remote play ships sooner. No delivery dates are committed until the technical prototypes establish their scope.
