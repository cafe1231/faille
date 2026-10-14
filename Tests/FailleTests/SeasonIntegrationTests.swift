import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

/// Intégration 1 (spec saison §2.1, §3.5, §3.7, §3.8) : lien profond inchangé, saison d'exemple branchée, ligues suivies,
/// révélation d'un classement, onboarding d'un utilisateur existant, Dynamic Type.
@Suite(.serialized)
@MainActor
struct SeasonIntegrationTests {
    /// Le lien profond d'une notification ouvre toujours le Détail dans l'onglet Matchs, sans source de zoom.
    @Test func notificationDeepLinkStillOpensTheDetailInMatches() {
        let link = RootNavigation.deepLink(matchId: "m1")
        #expect(link.tab == .matches)
        #expect(link.route == MatchRoute(matchId: "m1"))
        #expect(link.route.sourceID == nil)
    }

    @Test func previewStoresCarryTheSeasonSample() {
        #expect(AppStore(preview: .standard).season.matches.isEmpty)   // planches existantes inchangées
        let store = AppStore(preview: .withSeason)
        #expect(!store.season.matches.isEmpty)
        #expect(store.season.isPreview)
        // T1 est en anti-spoiler dans les aperçus : ses trois matchs d'exemple sont masqués.
        #expect(store.seasonMasked == ["m-t1-blg", "m-t1-hle", "m-gen-t1"])
        #expect(AppStore(preview: .withSeasonLoading).season.isLoaded == false)
    }

    /// Effectifs du catalogue d'exemple = joueurs des games d'exemple (mêmes ids).
    @Test func sampleRostersMatchTheSampleGames() {
        let ids = Set(SeasonSamples.games.flatMap { $0.blue.players + $0.red.players }.map(\.playerId))
        let roster = SampleData.catalog.flatMap { $0.players ?? [] }
        #expect(roster.count == 15)
        #expect(roster.allSatisfy { ids.contains($0.id) })
    }

    @Test func standingsAreMaskedUntilRevealed() {
        let store = AppStore(preview: .withSeason)
        // Le Mondial contient des matchs masqués de T1 (anti-spoiler) ; la LEC non.
        #expect(store.isStandingsMasked(tournamentId: SeasonSamples.worlds.id))
        #expect(!store.isStandingsMasked(tournamentId: SeasonSamples.lecSplit3.id))
        store.revealStandings(tournamentId: SeasonSamples.worlds.id)
        #expect(!store.isStandingsMasked(tournamentId: SeasonSamples.worlds.id))
        // Révéler le classement ne révèle aucun match.
        #expect(store.seasonMasked == ["m-t1-blg", "m-t1-hle", "m-gen-t1"])
    }

    @Test func followingALeagueIsSavedAndWakesTheCollection() throws {
        let files = TemporaryFiles.store()
        let store = AppStore(transport: StubTransport(), files: files)
        let lec = League(id: "98767991302996019", slug: "lec", name: "LEC", region: "EMEA", image: nil, priority: 1)
        store.toggleFollowLeague(lec)
        #expect(store.follows.leagues.map(\.id) == [lec.id])
        #expect(store.season.wakePending)
        let saved = try #require(files.load(FollowList.self, from: .follows))
        #expect(saved.leagues.map(\.slug) == ["lec"])
        store.toggleFollowLeague(lec)
        #expect(store.follows.leagues.isEmpty)
        store.endScene()
    }

    /// Un utilisateur qui suit déjà des équipes ne voit pas l'onboarding ; un nouveau, si.
    @Test func existingUsersSkipTheOnboarding() {
        let existing = TemporaryFiles.store()
        existing.save(SampleData.follows, to: .follows)
        let store = AppStore(transport: StubTransport(), files: existing)
        #expect(store.settings.onboardingDone)
        #expect(!store.showsOnboarding)
        #expect(existing.load(AppSettings.self, from: .settings)?.onboardingDone == true)
        let fresh = AppStore(transport: StubTransport(), files: TemporaryFiles.store())
        #expect(fresh.showsOnboarding)
        fresh.completeOnboarding()
        #expect(!fresh.showsOnboarding)
    }

    /// Dynamic Type : taille de `Typo` à la taille par défaut, plus grande au-delà, plafonnée à `accessibility2`.
    @Test func soraStylesScaleWithDynamicTypeUpToACap() {
        #expect(SoraStyle.body.pointSize(for: .large) == 15)
        #expect(SoraStyle.title.pointSize(for: .large) == 32)
        #expect(SoraStyle.body.pointSize(for: .accessibility1) > 15)
        #expect(SoraStyle.body.pointSize(for: .accessibility5) == SoraStyle.body.pointSize(for: .accessibility2))
    }

    @Test func seasonPartsSpeakTheForm() {
        let form = [FormPip(matchId: "a", outcome: .win), FormPip(matchId: "b", outcome: .loss),
                    FormPip(matchId: "c", outcome: .masked)]
        #expect(FormPips.spoken(form) == "Victoire, Défaite, Masqué")
    }

    /// I-1 : un match à venir d'une équipe dont le dernier match est masqué est caché (ligne fixe, pas de pastille), tant
    /// qu'il n'est pas révélé ; un autre match, ou une équipe non masquée, n'est pas touché.
    @Test func upcomingMatchOfAMaskedTeamIsHidden() {
        func event(_ id: String, _ state: EventState, teams: [String?]) -> MatchEvent {
            MatchEvent(startTime: Date(timeIntervalSince1970: 1_800_000_000), state: state, type: "match", blockName: nil,
                       league: LeagueRef(id: nil, slug: "lck", name: "LCK", image: nil),
                       match: MatchInfo(id: id,
                                        teams: teams.map { MatchTeam(id: $0, name: "T", code: "T", image: nil, result: nil) },
                                        strategy: nil, games: nil),
                       streams: nil)
        }
        let upcoming = event("m-up", .unstarted, teams: ["t1", "g2"])
        #expect(MatchLine.isHiddenUpcoming(upcoming, maskedTeamIds: ["t1"], revealed: []))
        #expect(!MatchLine.isHiddenUpcoming(upcoming, maskedTeamIds: ["t1"], revealed: ["m-up"]))
        #expect(!MatchLine.isHiddenUpcoming(upcoming, maskedTeamIds: ["kc"], revealed: []))
        #expect(!MatchLine.isHiddenUpcoming(event("m-done", .completed, teams: ["t1", "g2"]), maskedTeamIds: ["t1"],
                                            revealed: []))
        #expect(!MatchLine.isHiddenUpcoming(event("m-none", .unstarted, teams: [nil, nil]), maskedTeamIds: ["t1"],
                                            revealed: []))
    }

    /// I-2 : la session de collecte (budget) ne repart de zéro qu'après un vrai passage en arrière-plan.
    @Test func collectionSessionRestartsOnlyAfterABackgroundPassage() async {
        let store = AppStore(transport: StubTransport(), files: TemporaryFiles.store())
        #expect(!store.seasonSessionPending)
        #expect(await store.startSeasonSessionIfNeeded() == false)
        store.noteBackgroundPassage()
        #expect(store.seasonSessionPending)
        #expect(await store.startSeasonSessionIfNeeded())
        #expect(!store.seasonSessionPending)
        #expect(await store.startSeasonSessionIfNeeded() == false)
    }
}
