import Foundation
import LoLKit

/// Frames d'exemple d'une game, minute par minute, pour les aperçus et les tests (aucune requête) : construites avec les
/// inits publics de LoLKit à partir d'un scénario (écart de gold, kills par joueur, drakes, barons, tours, inhibiteurs).
enum TimelineSamples {
    /// Un scénario de game, minute par minute.
    struct Script: Sendable {
        /// Écart de gold (bleu − rouge) à chaque minute, de 0:00 à la dernière frame.
        let goldDiffs: [Int]
        /// Kills : minute, et index (0-4, ordre du flux) du joueur qui tue.
        let blueKills: [(minute: Int, player: Int)]
        let redKills: [(minute: Int, player: Int)]
        let blueDragons: [(minute: Int, type: String)]
        let redDragons: [(minute: Int, type: String)]
        let blueBarons: [Int]
        let redBarons: [Int]
        let blueTowers: [Int]
        let redTowers: [Int]
        let blueInhibitors: [Int]
        let redInhibitors: [Int]
        /// La dernière frame est `finished`.
        let finished: Bool

        /// KC – C9, game 2 en cours (18 min) : finit sur les stats de `SampleData.kcSnapshot` (7 – 4, +2,1k, 3 – 1 tours,
        /// drakes infernal et océan contre nuage).
        static let kcLive = Script(
            goldDiffs: [0, 0, 30, 80, 260, 140, -120, 60, 480, 620, 540, 900, 760, 1_100, 1_480, 1_300, 1_720, 1_900,
                        2_100],
            blueKills: [(4, 2), (8, 0), (8, 1), (11, 2), (14, 0), (16, 2), (18, 3)],
            redKills: [(6, 1), (9, 2), (12, 2), (15, 3)],
            blueDragons: [(9, "infernal"), (15, "ocean")],
            redDragons: [(5, "cloud")],
            blueBarons: [], redBarons: [],
            blueTowers: [13, 16, 17], redTowers: [12],
            blueInhibitors: [], redInhibitors: [],
            finished: false
        )

        /// Game jouée de 34 min, gagnée par l'équipe rouge : le fil et la courbe de l'aperçu `19-fil-et-courbe`.
        static let redWins = Script(
            goldDiffs: [0, -20, 40, -80, -150, -300, -220, -480, -700, -540, -900, -1_250, -1_100, -1_600, -2_100,
                        -1_800, -2_300, -2_900, -3_400, -3_100, -3_900, -4_600, -5_200, -4_800, -5_600, -6_900, -7_400,
                        -8_100, -8_800, -9_600, -10_500, -11_800, -12_600, -13_900, -15_200],
            blueKills: [(6, 1), (13, 2), (19, 3), (24, 0), (27, 2)],
            redKills: [(4, 2), (9, 1), (9, 2), (14, 3), (17, 0), (20, 2), (22, 3), (25, 1), (28, 2), (30, 3), (31, 0),
                       (33, 2), (33, 3), (34, 1)],
            blueDragons: [(11, "ocean")],
            redDragons: [(6, "hextech"), (17, "hextech"), (23, "infernal"), (29, "hextech")],
            blueBarons: [], redBarons: [26, 33],
            blueTowers: [15, 21], redTowers: [12, 14, 18, 20, 24, 27, 29, 31, 32, 33, 34],
            blueInhibitors: [], redInhibitors: [31, 33, 34],
            finished: true
        )
    }

    /// Une frame par minute, de 0:00 à la fin du scénario (horodatée 9 s après chaque minute pleine, comme la relecture).
    /// Équipes, joueurs (rôle, champion, pseudo) et valeurs finales de chaque joueur viennent de `final` ; les kills de
    /// chaque joueur suivent le scénario (le fil peut donc les nommer), le reste croît au prorata du temps.
    static func frames(_ script: Script, start: Date, final: GameSnapshot) -> [GameSnapshot] {
        let last = script.goldDiffs.count - 1
        return script.goldDiffs.indices.map { minute in
            let base = 2_500 + minute * 1_750
            let diff = script.goldDiffs[minute]
            func count(_ minutes: [Int]) -> Int { minutes.filter { $0 <= minute }.count }
            let blue = TeamStats(kills: script.blueKills.filter { $0.minute <= minute }.count, gold: base + diff / 2,
                                 towers: count(script.blueTowers), inhibitors: count(script.blueInhibitors),
                                 barons: count(script.blueBarons),
                                 dragons: script.blueDragons.filter { $0.minute <= minute }.map(\.type))
            let red = TeamStats(kills: script.redKills.filter { $0.minute <= minute }.count, gold: base - diff / 2,
                                towers: count(script.redTowers), inhibitors: count(script.redInhibitors),
                                barons: count(script.redBarons),
                                dragons: script.redDragons.filter { $0.minute <= minute }.map(\.type))
            return GameSnapshot(
                gameId: final.gameId,
                phase: script.finished && minute == last ? .finished : .inGame,
                timestamp: start.addingTimeInterval(Double(minute) * 60 + (minute == 0 ? 0 : 9)),
                blueTeamId: final.blueTeamId, redTeamId: final.redTeamId, blue: blue, red: red,
                bluePlayers: players(final.bluePlayers, kills: script.blueKills, minute: minute, last: last),
                redPlayers: players(final.redPlayers, kills: script.redKills, minute: minute, last: last)
            )
        }
    }

    /// Joueurs à la minute `minute` : kills exacts du scénario, le reste au prorata de leur ligne finale.
    private static func players(_ finals: [PlayerLine], kills: [(minute: Int, player: Int)], minute: Int,
                                last: Int) -> [PlayerLine] {
        let share = last == 0 ? 1 : Double(minute) / Double(last)
        func part(_ value: Int) -> Int { Int((Double(value) * share).rounded()) }
        return finals.enumerated().map { index, final in
            PlayerLine(role: final.role, champion: final.champion, name: final.name, level: max(1, part(final.level)),
                       kills: kills.filter { $0.minute <= minute && $0.player == index }.count,
                       deaths: part(final.deaths), assists: part(final.assists), creepScore: part(final.creepScore),
                       gold: 500 + part(final.gold - 500))
        }
    }
}
