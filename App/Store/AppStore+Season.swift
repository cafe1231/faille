import Foundation
import LoLKit

/// Saison dans l'appli (spec saison §1-§3) : contexte et boucle de la collecte, masquages, noms, aperçus.
extension AppStore {
    // MARK: Collecte

    /// Ce que la collecte lit de l'appli, relu avant chaque game (spec saison §1.6).
    func seasonContext() -> SeasonContext {
        SeasonContext(follows: follows, leagues: leagues, catalog: catalog, revealed: settings.revealedMatchIds,
                      openedTeamId: season.openedTeamId, now: Date())
    }

    /// Un vrai passage en arrière-plan a eu lieu (`enterBackground`) : la prochaine session de collecte remet le budget
    /// à zéro (I-2). Sans lui, une scène qui redevient active (changement de `scenePhase` sans vraie mise en arrière-plan)
    /// ne rend pas 300 requêtes de plus.
    func noteBackgroundPassage() {
        seasonSessionPending = true
    }

    /// Démarre une nouvelle session de collecte si un passage en arrière-plan l'a demandé ; rend vrai si elle a démarré.
    @discardableResult
    func startSeasonSessionIfNeeded() async -> Bool {
        guard seasonSessionPending else { return false }
        seasonSessionPending = false
        await season.beginSession()
        return true
    }

    /// Boucle de la collecte, troisième tâche de `poll` (spec saison §1.6) : premier plan seulement, annulée avec la
    /// scène (jamais pendant un réveil d'arrière-plan : `refreshInBackground` ne l'appelle pas). Le budget n'est remis à
    /// zéro qu'après un vrai passage en arrière-plan (`startSeasonSessionIfNeeded`). Un tour d'attente d'abord (le premier
    /// rafraîchissement passe avant) ; puis une passe tant que l'API répond et que les ligues sont connues ; entre deux
    /// passes, 30 min ou un réveil (`season.wake()`).
    ///
    /// `crawl` rend `.cancelled` quand une passe tourne déjà (garde de réentrance de `SeasonStore`) : ce n'est pas une fin
    /// de passe. La boucle ne la relance pas en rond ; elle attend le prochain réveil comme après toute autre fin.
    func seasonLoop() async {
        guard !season.isPreview else { return }
        await startSeasonSessionIfNeeded()
        await season.loadFromDisk()
        // Jointure résultats + classements avec le catalogue et les ligues du moment (I-10).
        season.rejoin(catalog: catalog, leagues: leagues)
        try? await Task.sleep(for: .seconds(RefreshPolicy.tick))
        while !Task.isCancelled {
            if !isFailing, !leagues.isEmpty {
                // Catalogue et ligues ont pu arriver du réseau depuis : la jointure les reprend avant chaque passe.
                season.rejoin(catalog: catalog, leagues: leagues)
                await season.crawl { self.seasonContext() }
            }
            guard !Task.isCancelled else { break }
            await season.waitForWake(maxSeconds: 30 * 60)
        }
    }

    /// Page d'équipe ouverte / fermée : priorité 0 de la collecte (équipe non suivie, tournoi en cours).
    func openTeamPage(_ teamId: String) {
        season.open(teamId: teamId)
    }

    func closeTeamPage(_ teamId: String) {
        season.close(teamId: teamId)
    }

    // MARK: Anti-spoiler

    /// Matchs de la saison masqués (spec saison §1.8) : à passer à toute stat de saison.
    var seasonMasked: Set<String> {
        SeasonMasking.maskedMatchIds(season.matches, follows: follows, revealed: settings.revealedMatchIds)
    }

    /// Classement d'un tournoi masqué (spec saison §3.5, `StandingsMasking`) : une équipe suivie en anti-spoiler y figure
    /// avec un match masqué (ou un bilan que ses matchs révélés ne couvrent pas), sans révélation du classement.
    func isStandingsMasked(tournamentId: String) -> Bool {
        guard let standings = season.standings[tournamentId] else { return false }
        return StandingsMasking.isMasked(standings, tournamentId: tournamentId, follows: follows,
                                         revealed: settings.revealedMatchIds,
                                         revealedStandings: settings.revealedStandingIds)
    }

    /// Tournois dont le classement est masqué (« À ne pas rater » : leurs raisons tirées des résultats valent 0).
    var maskedStandingIds: Set<String> {
        Set(season.standings.keys.filter { isStandingsMasked(tournamentId: $0) })
    }

    /// Équipes suivies en anti-spoiler dont le dernier match est masqué (règles F1/C), sur toutes les cartes.
    var maskedLatestTeamIds: Set<String> {
        Presenter.maskedLatestTeamIds(cards, follows: follows, revealed: settings.revealedMatchIds)
    }

    /// Match à venir non révélé d'une équipe dont le dernier match est masqué (I-1) : jamais de ligne, de pastille ni de
    /// jour de calendrier qui le trahisse.
    func isUpcomingMasked(_ event: MatchEvent) -> Bool {
        guard event.state == .unstarted else { return false }
        return MatchLine.isHiddenUpcoming(event, maskedTeamIds: maskedLatestTeamIds, revealed: settings.revealedMatchIds)
    }

    /// `events` sans les matchs à venir masqués : à passer à `HomeModel.compute` et à `CalendarMonth.days` (pastilles).
    func withoutMaskedUpcoming(_ events: [MatchEvent]) -> [MatchEvent] {
        let masked = maskedLatestTeamIds
        guard !masked.isEmpty else { return events }
        let revealed = settings.revealedMatchIds
        return events.filter { !MatchLine.isHiddenUpcoming($0, maskedTeamIds: masked, revealed: revealed) }
    }

    // MARK: Premier lancement

    /// Onboarding au premier lancement (spec saison §3.7) : pas fait, et rien n'est suivi.
    var showsOnboarding: Bool {
        !settings.onboardingDone && follows.teams.isEmpty && follows.leagues.isEmpty
    }

    // MARK: Noms

    func team(id: String) -> Team? {
        catalog.first { $0.id == id }
    }

    /// Nom d'une équipe : catalogue, sinon celui d'un match de la saison, sinon l'id.
    func teamName(id: String) -> String {
        if let team = team(id: id) { return team.name }
        for match in season.matches {
            if let team = match.teams.first(where: { $0.id == id }) { return team.name }
        }
        return id
    }

    func teamCode(id: String) -> String? {
        if let team = team(id: id) { return team.code }
        for match in season.matches {
            if let team = match.teams.first(where: { $0.id == id }) { return team.code }
        }
        return nil
    }

    /// Pseudo d'un joueur (spec saison §1.5) : catalogue, sinon pseudo du flux sans le code de son équipe.
    func playerName(id: String, raw: String, teamId: String?) -> String {
        SeasonNames.player(id, raw: raw, teamCode: teamId.flatMap { teamCode(id: $0) }, catalog: catalog)
    }

    func league(id: String) -> League? {
        leagues.first { $0.id == id }
    }

    /// Tournoi en cours d'une ligue (lien « Classement ») ; nil tant que ses tournois ne sont pas lus.
    func currentTournamentId(leagueId: String, now: Date = Date()) -> String? {
        SeasonPlanning.currentTournamentIds(season.tournaments, leagueIds: [leagueId], now: now).first
    }

    // MARK: Aperçus

    static func seasonPreview(_ sample: SeasonSample) -> SeasonPreview {
        switch sample {
        case .none: SeasonPreview()
        case .standard: SeasonSamples.standard
        case .collecting: SeasonSamples.collecting
        case .loading: SeasonSamples.loading
        }
    }
}
