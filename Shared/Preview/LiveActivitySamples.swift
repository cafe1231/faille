import Foundation
import LoLKit

/// Live Activities d'exemple (aperçus PNG, #Preview), une par état de la spec §6.3, comme les maquettes ① et ②.
/// Les dates partent de l'heure du rendu : le chrono affiche « 18:42 » et « màj il y a 9 min » au moment de la capture.
enum LiveActivitySamples {
    /// KC (suivie) contre C9, Mondial Bo5.
    static let kc = LiveMatchAttributes(
        matchId: SampleData.kcMatchId, leagueName: "Mondial", bestOf: 5,
        teams: [.init(id: "kc", code: "KC", name: "Karmine Corp", colorHex: "#5B8CFF"),
                .init(id: "c9", code: "C9", name: "Cloud9 Kia", colorHex: nil)],
        primaryTeamIndex: 0)

    /// T1 (suivie, en anti-spoiler) contre FLY.
    static let t1 = LiveMatchAttributes(
        matchId: SampleData.t1MatchId, leagueName: "Mondial", bestOf: 5,
        teams: [.init(id: "t1", code: "T1", name: "T1", colorHex: "#FF5C7A"),
                .init(id: "fly", code: "FLY", name: "FlyQuest", colorHex: nil)],
        primaryTeamIndex: 0)

    /// Match épinglé à la main, aucune équipe suivie : verre neutre.
    static let kcb = LiveMatchAttributes(
        matchId: "m-kcb-sly", leagueName: "LFL", bestOf: 3,
        teams: [.init(id: "kcb", code: "KCB", name: "Karmine Corp Blue", colorHex: nil),
                .init(id: "sly", code: "SLY", name: "Solary", colorHex: nil)],
        primaryTeamIndex: nil)

    static let stats = [
        TeamStats(kills: 7, gold: 32_400, towers: 3, inhibitors: 0, barons: 0, dragons: ["infernal", "ocean"]),
        TeamStats(kills: 4, gold: 30_300, towers: 1, inhibitors: 0, barons: 0, dragons: ["cloud"]),
    ]

    private static func state(_ phase: LiveMatchState.Phase, score: [Int]?, game: Int?, clockStart: Date? = nil,
                              stoppedAt: Date? = nil, stats: [TeamStats]? = nil, statsAvailable: Bool = true,
                              winner: String? = nil, updatedAt: Date = Date()) -> LiveMatchState {
        LiveMatchState(phase: phase, seriesScore: score, gameNumber: game, gameClockStart: clockStart,
                       gameClockStoppedAt: stoppedAt, stats: stats, statsAvailable: statsAvailable,
                       spoilerFree: false, winnerCode: winner, updatedAt: updatedAt)
    }

    /// Maquette ① : KC 1 – 0 C9, game 2, chrono à 18:42, stats.
    static var inGame: LiveActivityDisplay {
        LiveActivityDisplay(attributes: kc,
                            state: state(.inGame, score: [1, 0], game: 2,
                                         clockStart: Date().addingTimeInterval(-1122), stats: stats),
                            isStale: false)
    }

    /// Game en pause dans le flux : le chrono est figé.
    static var clockStopped: LiveActivityDisplay {
        LiveActivityDisplay(attributes: kc,
                            state: state(.inGame, score: [1, 1], game: 3, clockStart: Date().addingTimeInterval(-1500),
                                         stoppedAt: Date().addingTimeInterval(-30), stats: stats),
                            isStale: false)
    }

    /// T1 en anti-spoiler : ni score, ni game, ni stats.
    static var masked: LiveActivityDisplay {
        LiveActivityDisplay(attributes: t1,
                            state: state(.inGame, score: [1, 0], game: 2, clockStart: Date().addingTimeInterval(-600),
                                         stats: stats).masked(),
                            isStale: false)
    }

    /// Pas fraîche : dernière relecture il y a 9 min, stats pâlies.
    static var stale: LiveActivityDisplay {
        let older = [
            TeamStats(kills: 5, gold: 24_100, towers: 2, inhibitors: 0, barons: 0, dragons: ["infernal"]),
            TeamStats(kills: 4, gold: 23_300, towers: 1, inhibitors: 0, barons: 0, dragons: ["cloud"]),
        ]
        return LiveActivityDisplay(attributes: kc,
                                   state: state(.inGame, score: [1, 0], game: 2,
                                                clockStart: Date().addingTimeInterval(-1500), stats: older,
                                                updatedAt: Date().addingTimeInterval(-540)),
                                   isStale: true)
    }

    /// KC 2 – 0, la game 3 va commencer.
    static var betweenGames: LiveActivityDisplay {
        LiveActivityDisplay(attributes: kc, state: state(.betweenGames, score: [2, 0], game: 3), isStale: false)
    }

    /// Victoire KC 3 – 1.
    static var finished: LiveActivityDisplay {
        LiveActivityDisplay(attributes: kc, state: state(.finished, score: [3, 1], game: nil, winner: "KC"),
                            isStale: false)
    }

    /// Riot ne fournit pas les stats : score et chrono seulement.
    static var statsUnavailable: LiveActivityDisplay {
        LiveActivityDisplay(attributes: kcb,
                            state: state(.inGame, score: [0, 0], game: 1, clockStart: Date().addingTimeInterval(-1330),
                                         statsAvailable: false),
                            isStale: false)
    }
}
