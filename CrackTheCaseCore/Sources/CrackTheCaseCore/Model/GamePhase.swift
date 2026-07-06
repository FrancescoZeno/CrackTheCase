import Foundation

/// The current phase of a game session, mirrored from host to every client.
///
/// `.minigame` through `.notebook` repeat every round (see
/// `GameSession.beginNextRound()`); `.voting`/`.victory`/`.defeat` can
/// interrupt that loop at any `.notebook`, and `.blackoutReveal`/
/// `.blackoutTask` replace a single round's `.minigame` beat once per game.
public enum GamePhase: Codable, Sendable, Equatable {
    /// The client has not yet joined a host session.
    case connecting
    /// Players are picking a nickname and toggling "Ready".
    case lobby
    /// All players are ready; the host is transitioning into the game proper.
    case starting
    /// The Apple TV plays the introductory story video (skippable).
    case introVideo
    /// The Apple TV shows the rulebook (skippable).
    case rules
    /// Players race to finish an identical minigame; arrival order sets the
    /// turn order for room exploration, and the last to finish is penalized.
    case minigame
    /// Players take turns exploring one of the 9 rooms and reading what (if
    /// anything) they found there.
    case roomSelection
    /// The Apple TV shows the 6 suspects while each player works their own
    /// notebook, marking off who they've ruled out.
    case notebook
    /// One player is accusing a suspect; everyone else is locked out until
    /// the result comes in.
    case voting
    /// A player accused the actual culprit — the game is over.
    case victory
    /// Round `GameSession.maxRoundNumber` finished its notebook phase
    /// without anyone accusing the actual culprit — everyone loses. Reached
    /// the same way as `.victory` (from `.notebook`, via `beginNextRound()`),
    /// just by running out of rounds instead of by a correct accusation.
    case defeat
    /// The Apple TV shows the black-out narrative beat: lights out, 2 of
    /// the 3 clues have just relocated. Happens exactly once per game.
    case blackoutReveal
    /// All players must complete an identical, simultaneous task before
    /// the normal round cycle resumes.
    case blackoutTask
    /// Too many players disconnected mid-game to continue (the game
    /// requires at least `GameSession.minimumPlayerCount`). The host must
    /// acknowledge this on the board to return everyone to `.lobby`.
    case notEnoughPlayers
}
