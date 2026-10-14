import Foundation
import LoLKit
import Testing
@testable import Faille

struct PlayerPageModelTests {
    @Test func playerIdentityPrefersTheCatalogAndStripsTheTeamPrefixOtherwise() {
        let games = SeasonSamples.games
        let identity = PlayerPageModel.identity("p-caps", catalog: SampleData.catalog, games: games)
        #expect(identity?.name == "Caps")
        #expect(identity?.role == "mid")
        #expect(identity?.teamId == "g2")
        #expect(PlayerPageModel.identity("nobody", catalog: [], games: games) == nil)
    }

    /// Faker (T1, en anti-spoiler dans les aperçus) : ses 3 matchs d'exemple sont masqués ; le compte vient des matchs
    /// de l'équipe, pas des games (ruling I-9) : il tient même sans aucune game de T1.
    @Test func maskedMatchCountComesFromTheTeamMatchesNotTheGames() {
        let masked = SeasonMasking.maskedMatchIds(SeasonSamples.matches, follows: SampleData.follows, revealed: [])
        let withGames = PlayerPageModel.identity("p-faker", catalog: SampleData.catalog, games: SeasonSamples.games)
        #expect(PlayerPageModel.maskedMatchCount(teamId: withGames?.teamId, matches: SeasonSamples.matches,
                                                 masked: masked) == 3)
        let noGames = PlayerPageModel.identity("p-faker", catalog: SampleData.catalog, games: [])
        #expect(noGames?.teamId == "t1")
        #expect(PlayerPageModel.maskedMatchCount(teamId: noGames?.teamId, matches: SeasonSamples.matches,
                                                 masked: masked) == 3)
        #expect(PlayerPageModel.maskedMatchCount(teamId: nil, matches: SeasonSamples.matches, masked: masked) == 0)
        #expect(PlayerPageModel.maskedMatchCount(teamId: "kc", matches: SeasonSamples.matches, masked: []) == 0)
    }
}
