import Foundation
import LoLKit

/// Données des fonctionnalités pour les aperçus (#Preview et PNG), aucune requête : fil et courbe, détails par joueur et
/// sorts d'invocateur des deux games que montrent les aperçus — KC – C9 game 2 en direct (`SampleData.kcSnapshot`) et
/// la game 4 terminée de KC – G2 (`SampleData.kcG2Final`).
enum FeatureSamples {
    static var timelines: [String: [GameSnapshot]] {
        [
            SampleData.kcSnapshot.gameId: TimelineSamples.frames(.kcLive, start: SampleData.kcGameStart,
                                                                 final: SampleData.kcSnapshot) + [SampleData.kcSnapshot],
            SampleData.kcG2Final.gameId: TimelineSamples.frames(.redWins, start: SampleData.kcG2GameStart,
                                                                final: SampleData.kcG2Final),
        ]
    }

    static var details: [String: GameDetails] {
        [
            SampleData.kcSnapshot.gameId: BuildSamples.details(for: SampleData.kcSnapshot),
            SampleData.kcG2Final.gameId: BuildSamples.details(for: SampleData.kcG2Final),
        ]
    }

    /// Sorts d'invocateur de la game terminée (comme Leaguepedia les donne, en ids Data Dragon).
    static var spells: [String: [String: [String]]] {
        [
            SampleData.kcG2Final.gameId: [
                "Gnar": ["SummonerFlash", "SummonerTeleport"], "Sejuani": ["SummonerSmite", "SummonerFlash"],
                "Orianna": ["SummonerFlash", "SummonerTeleport"], "Varus": ["SummonerFlash", "SummonerBoost"],
                "Braum": ["SummonerFlash", "SummonerExhaust"], "Rumble": ["SummonerFlash", "SummonerTeleport"],
                "LeeSin": ["SummonerFlash", "SummonerSmite"], "Ahri": ["SummonerFlash", "SummonerDot"],
                "Kalista": ["SummonerFlash", "SummonerHeal"], "Rakan": ["SummonerFlash", "SummonerDot"],
            ],
        ]
    }
}
