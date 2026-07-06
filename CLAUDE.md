# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

CrackTheCase ("Phoenix Academy") is a local-network party/mystery game built
as two native SwiftUI app targets plus a shared Swift Package:

- **CrackTheCase** — tvOS target (`SDKROOT = appletvos`), source in `CrackTheCase/`. This is the **host**: it runs `HostConnectivityService`, owns the single `GameSession`, and is the "board" every phone looks at.
- **CrackTheCaseIos** — iOS target (`SDKROOT = iphoneos`, iPhone + iPad), source in `CrackTheCaseIos/`. This is the **client/controller**: each player's phone runs `ClientConnectivityService` and only ever mirrors state the host broadcasts.
- **CrackTheCaseCore** — a local Swift package (`CrackTheCaseCore/`, referenced via `XCLocalSwiftPackageReference`) containing all shared game logic: models, phases, and the MultipeerConnectivity networking layer. Both app targets depend on it; it has no dependency on either app target. This is where nearly all non-UI logic lives and should be extended first.

Devices connect over **MultipeerConnectivity** (Bonjour service type
`crackthecase`, declared in both targets' `Info.plist` as `NSBonjourServices`
— must stay in sync with `PeerService.type`). One Apple TV advertises a
session with a 4-digit join code; phones browse, invite, and connect,
forming a star topology (the host creates a dedicated `MCSession` per
invited peer specifically to avoid multipeer's mesh topology, which was
unstable with 3+ clients).

There is no Xcode-project-level README; `LORE.md` has the game's narrative
premise (a murder mystery at a boarding school, players are investigators
racing a countdown), `tasks.md` and `minigiochi.md` are Italian-language
design notes describing the 13 turn-order minigames and 3 Black-out
emergency-task minigames respectively — useful for understanding *why* a
given `TurnMinigame`/`BlackoutMinigame` case behaves the way it does.

## Common commands

Build/run is via Xcode or `xcodebuild` from the repo root (where
`CrackTheCase.xcodeproj` lives).

```bash
# List schemes/targets
xcodebuild -list -project CrackTheCase.xcodeproj

# Build the iOS target for the simulator
xcodebuild -project CrackTheCase.xcodeproj -scheme CrackTheCaseIos \
  -destination 'generic/platform=iOS Simulator' build

# Build the tvOS target for the simulator
xcodebuild -project CrackTheCase.xcodeproj -scheme CrackTheCase \
  -destination 'generic/platform=tvOS Simulator' build
```

The app targets have no test target. All automated tests live in the
`CrackTheCaseCore` Swift package instead and run via SwiftPM (Swift Testing,
not XCTest):

```bash
cd CrackTheCaseCore

# Run the full suite
swift test

# Run a single test suite
swift test --filter GameSessionTests

# Run a single test
swift test --filter GameSessionTests/someTestMethodName
```

Note the package's `Package.swift` pins a macOS 14 minimum purely so
`swift test` (which builds against macOS on a Mac host) has Observation
framework support for `@Observable` — the app targets' real deployment
targets are iOS/tvOS 26.

Real MultipeerConnectivity behavior (advertising, browsing, joins,
disconnect/reconnect handling) cannot be exercised by `swift test` — verify
that by running the tvOS and iOS builds on real devices (or two
simulators/devices on the same network), not by unit tests.

## Architecture

### Networking is one-directional and rebroadcast-based

`GameSession` (in `Model/GameSession.swift`) is the single source of truth
and only ever lives on the host (Apple TV). It is `@MainActor @Observable`,
mutated only by `HostConnectivityService`. Clients never construct or mutate
a `GameSession` — `ClientConnectivityService` (in `Net/`) exposes a flat,
mirrored set of `@MainActor private(set)` properties that it updates purely
by decoding the host's broadcast `GameMessage.sessionState` payload.

`GameMessage` (`Net/GameMessage.swift`) is the entire wire protocol — a
single `Codable` enum shared by both sides, split into a client→host half
(`requestToJoin`, `join`, `setReady`, `chooseRoom`, `castAccusation`, …) and
a host→client half (`sessionState`, `startGame`, `roomFinding`, `joinResult`,
`kicked`). When adding a new piece of synced state, extend this enum and the
`sessionState` case's payload rather than inventing a second message type —
and mirror the new field on both `GameSession` (host) and
`ClientConnectivityService` (client).

**Secrecy boundary**: `sessionState` deliberately never carries clue
content, which suspect is actually guilty, or the round the Black-out event
will trigger on — only public facts safe to show on the shared tvOS board
(who visited which room, vote outcomes once resolved, whether the *current*
round is Black-out). Private per-player info (a room's clue) goes out via
the separate `.roomFinding` message sent only to that one player. Keep this
boundary in mind when adding new state: "safe for every screen to see" vs
"only this player should see this" determines whether it belongs in
`sessionState` or a targeted message.

### Game flow is a phase state machine

`GamePhase` (`Model/GamePhase.swift`) enumerates every screen the host and
clients render, and its doc comment describes the overall loop:
`.minigame → .roomSelection → .notebook` repeats every round; `.voting`/
`.victory` can interrupt that loop from `.notebook`; `.blackoutReveal`/
`.blackoutTask` replace a single round's `.minigame` beat exactly once per
game (`GameSession.blackoutRoundNumber`, randomized 4–6 so players can't
predict it). Both `CrackTheCase/ContentView.swift` (tvOS board) and
`CrackTheCaseIos/ContentView.swift` (phone controller) are structured as a
single `switch` over the current phase, each case delegating to a
phase-specific view — read `GameSession.swift`'s method doc comments (e.g.
`beginNextRound()`, `beginBlackoutTask()`) before touching phase transitions,
since a lot of the sequencing logic (grace periods, held-back reveals,
turn-order bookkeeping) is non-obvious from the state shape alone.

Every phase-transition method exists in two places: an owning method on
`GameSession` doing the actual state mutation, and a thin wrapper on
`HostConnectivityService` that calls it and then broadcasts. Follow that
pattern for new transitions.

### Content is intentionally placeholder

Room names/icons (`Model/Room.swift`), suspect names/details
(`Model/Suspect.swift`), and clue text are explicitly marked as placeholder
narrative content standing in for the real mystery script (see `LORE.md`
for the intended story). Suspects are currently just named after their
`Avatar` color. Don't over-invest in polishing this copy without checking
whether it's meant to be replaced.

### Minigames

`TurnMinigame` (13 cases) decides the per-round race that sets room-
exploration turn order; `BlackoutMinigame` (3 cases) decides the one
simultaneous emergency task during the Black-out round. Each case has a
corresponding SwiftUI view in `CrackTheCaseIos/` (e.g. `TurnMinigame.numberMemory`
→ `TurnNumberMemoryView.swift`, `BlackoutMinigame.lightRegulator` →
`BlackoutLightRegulatorView.swift`) — these views only exist on the iOS
target since only players (not the shared tvOS board) actually play them.
`tasks.md` / `minigiochi.md` contain the original Italian design briefs each
minigame was built from, including win/fail conditions not always spelled
out in code comments.

### Local-only vs networked state

Not everything is synced: `PlayerIdentity`/`PlayerNickname` persist a
player's stable UUID and last-used nickname in `UserDefaults` so phones
reconnect as "the same" player across launches; `GameSettings` persists
per-device toggles (music/sound/haptics) that are deliberately never
broadcast — each device's settings are its own business. When adding new
per-player or per-device preferences, default to local `UserDefaults`
(follow the `GameSettings` key-namespacing pattern:
`"CrackTheCaseCore.<name>"`) rather than routing them through `GameMessage`.
