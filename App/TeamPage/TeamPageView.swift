import LoLKit
import SwiftUI

/// Ce que montre la page d'une équipe, assemblé depuis les stores (spec saison §3.1).
struct TeamPageContent {
    let teamId: String
    let name: String
    let code: String
    let image: String?
    let leagueName: String?
    let catalogTeam: Team?
    let followed: FollowedTeam?
    let scopes: [SeasonScope]
    let scope: SeasonScope?
    /// nil : aucun match connu de l'équipe dans la saison (« Les stats de cette équipe arrivent »).
    let season: TeamSeason?
    let upcoming: UpcomingLines
    let roster: [TeamPlayer]
    let standing: StandingLine?
    let standingLabel: String
    let opponentId: String?
    let headToHead: HeadToHead?

    /// Anti-spoiler : stats calculées sans les matchs masqués (`seasonMasked`), prochains matchs par `nextLine`,
    /// classement masqué selon `StandingsMasking`, face-à-face seulement si le prochain match est montré.
    @MainActor
    static func make(store: AppStore, teamId: String, scopeIndex: Int, now: Date) -> TeamPageContent {
        let catalogTeam = store.team(id: teamId)
        let seasonTeam = store.season.matches(ofTeam: teamId).first?.teams.first { $0.id == teamId }
        let followed = store.follows.team(id: teamId)
        let asFollowed = TeamPageModel.asFollowed(teamId, follows: store.follows, catalog: store.catalog, fallback: seasonTeam)
        let scopes = store.season.scopes(forTeam: teamId, now: now)
        let scope = scopes.isEmpty ? nil : scopes[min(max(scopeIndex, 0), scopes.count - 1)]
        let masked = store.seasonMasked
        let season = scope.flatMap { scope in
            scope.tournamentIds.isEmpty ? nil
                : store.season.teamSeason(teamId, scope: scope, masked: masked, now: now)
        }
        let rawUpcoming = asFollowed.map {
            TeamPageModel.upcoming(team: $0, schedule: store.schedule, live: store.live, follows: store.follows,
                                   revealed: store.settings.revealedMatchIds,
                                   maskedLatestTeamIds: store.maskedLatestTeamIds)
        } ?? .none
        // Anti-spoiler I-1 : même règle que l'Accueil et le calendrier (`withoutMaskedUpcoming`) ; un prochain match
        // retiré par la règle laisse « Prochain · masqué », jamais une ligne qui trahit.
        let upcoming: UpcomingLines
        if case let .matches(events) = rawUpcoming {
            let kept = store.withoutMaskedUpcoming(events)
            upcoming = kept.isEmpty ? .hidden : .matches(kept)
        } else {
            upcoming = rawUpcoming
        }
        let opponentId = asFollowed.flatMap { TeamPageModel.nextOpponentId(upcoming, team: $0, catalog: store.catalog) }
        let tournament = store.season.currentTournament(forTeam: teamId, now: now)
        let standing = tournament.flatMap { tournament in
            TeamPageModel.standing(teamId: teamId, tournamentId: tournament.id,
                                   standings: store.season.standings[tournament.id],
                                   masked: store.isStandingsMasked(tournamentId: tournament.id))
        }
        return TeamPageContent(
            teamId: teamId,
            name: catalogTeam?.name ?? seasonTeam?.name ?? followed?.name ?? teamId,
            code: catalogTeam?.code ?? seasonTeam?.code ?? followed?.code ?? "",
            image: catalogTeam?.image ?? seasonTeam?.image ?? followed?.image,
            leagueName: catalogTeam?.homeLeague?.name ?? followed?.homeLeagueName,
            catalogTeam: catalogTeam,
            followed: followed,
            scopes: scopes,
            scope: scope,
            season: season,
            upcoming: upcoming,
            roster: TeamPageModel.roster(catalogTeam),
            standing: standing,
            standingLabel: tournament.map(SeasonLabels.tournament) ?? "",
            opponentId: opponentId,
            headToHead: opponentId.map { SeasonStats.headToHead(teamId, $0, matches: store.season.matches, masked: masked) }
        )
    }
}

/// Page d'une équipe (spec saison §3.1) : en-tête, périmètres, bilan et forme, prochains matchs, effectif, moyennes,
/// champions, face-à-face, classement. Ouvrir la page lance la collecte priorité 0 de l'équipe (si elle n'est pas
/// suivie), la quitter l'arrête. Rien ne vient d'un match masqué ; si tous ses matchs le sont : « Stats masquées ».
struct TeamPageView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.seasonNow) private var fixedNow
    let teamId: String
    @State private var scopeIndex = 0
    @State private var haptics = HapticTrigger()
    @State private var cascaded = false
    @ReduceMotion var reduceMotion

    var body: some View {
        let content = TeamPageContent.make(store: store, teamId: teamId, scopeIndex: scopeIndex, now: fixedNow ?? Date())
        let shown = cascaded || !Motion.runs(.cascade, reduceMotion: reduceMotion)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TeamPageHeader(content: content, onToggleFollow: { toggleFollow(content) },
                               onToggleSpoiler: { toggleSpoiler(content) })
                if content.scopes.count > 1 {
                    scopePills(content.scopes)
                }
                if !store.season.isLoaded {
                    TeamPageSkeleton()
                } else {
                    seasonBlocks(content)
                }
                TeamUpcomingCard(lines: content.upcoming)
                    .cascadeIn(index: 3, shown: shown)
                if !content.roster.isEmpty {
                    TeamRosterCard(players: content.roster)
                        .cascadeIn(index: 4, shown: shown)
                }
                if let season = content.season, !TeamPageModel.allMasked(season), season.averages != nil {
                    TeamAveragesCard(season: season)
                    if !season.champions.isEmpty {
                        TeamChampionsCard(champions: season.champions)
                    }
                }
                if let opponentId = content.opponentId, let headToHead = content.headToHead {
                    TeamHeadToHeadCard(teamId: teamId, opponentId: opponentId, headToHead: headToHead,
                                       names: (content.code, store.teamCode(id: opponentId) ?? opponentId))
                }
                if let standing = content.standing {
                    TeamStandingCard(line: standing, tournamentLabel: content.standingLabel, onReveal: revealStandings)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .abyssBackground()
        .navigationTitle(content.name)
        .navigationBarTitleDisplayMode(.inline)
        .haptics(haptics)
        .onAppear {
            cascaded = true
            store.openTeamPage(teamId)
        }
        .onDisappear { store.closeTeamPage(teamId) }
    }

    @ViewBuilder private func seasonBlocks(_ content: TeamPageContent) -> some View {
        if let season = content.season {
            TeamSeasonStatus(season: season)
            if TeamPageModel.allMasked(season) {
                // Ruling spec §3.1 : pas de « révéler la saison » ; la page dit seulement combien de matchs sont masqués.
                NoteCard(icon: .eyeOff, text: String(localized: "Stats masquées · \(season.maskedMatches) matchs masqués"))
            } else {
                TeamRecordCard(season: season)
            }
        } else {
            NoteCard(icon: .clock, text: String(localized: "Les stats de cette équipe arrivent"))
        }
    }

    private func scopePills(_ scopes: [SeasonScope]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(scopes.enumerated()), id: \.offset) { index, scope in
                    PillButton(selected: index == min(scopeIndex, scopes.count - 1), action: {
                        if index != scopeIndex { haptics.play(.gamePicked) }
                        withAnimation(Motion.animation(.snappy, reduceMotion: reduceMotion)) { scopeIndex = index }
                    }) {
                        Text(SeasonLabels.scope(scope))
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
    }

    private func toggleFollow(_ content: TeamPageContent) {
        guard let team = content.catalogTeam else { return }
        haptics.play(content.followed == nil ? .follow : .unfollow)
        store.toggleFollow(team)
    }

    private func toggleSpoiler(_ content: TeamPageContent) {
        guard let followed = content.followed else { return }
        haptics.play(.spoilerToggle)
        withAnimation(Motion.fade) { store.setSpoilerFree(!followed.spoilerFree, id: followed.id) }
    }

    private func revealStandings(_ tournamentId: String) {
        haptics.play(.reveal)
        withAnimation(Motion.animation(.reveal, reduceMotion: reduceMotion)) {
            store.revealStandings(tournamentId: tournamentId)
        }
    }
}
