import Foundation
import LoLKit
import Observation
import os
import WidgetKit

/// Données de l'appli et leurs rafraîchissements (spec §4.1, §4.4, §10).
/// Au lancement, tout ce qui est sur le disque s'affiche aussitôt ; l'API prend ensuite le relais selon `RefreshPolicy`.
/// Les vues lisent ; toute action (suivre, masquer, révéler…) passe par ici et est enregistrée tout de suite.
@MainActor
@Observable
final class AppStore {
    // MARK: Données affichées

    private(set) var follows = FollowList()
    private(set) var settings = AppSettings()
    private(set) var leagues: [League] = []
    private(set) var catalog: [Team] = []
    private(set) var schedule: [MatchEvent] = []
    /// Réponse de `getLive` ; nil si inconnue ou trop vieille : les cartes retombent alors sur le calendrier.
    private(set) var live: [MatchEvent]? = nil
    /// Ligues en pilules de l'onglet Équipes, recalculées quand ligues, équipes ou calendrier changent.
    private(set) var leaguePills: [League] = []
    /// Détails des matchs ouverts dans l'écran Détail (`getEventDetails`), par id de match.
    private(set) var details: [String: EventDetails] = [:]
    /// Dernière frame connue de chaque game, et l'heure de l'appareil à laquelle elle a été reçue.
    private(set) var snapshots: [String: GameSnapshot] = [:]
    private(set) var snapshotDates: [String: Date] = [:]
    /// Première frame de chaque game en cours : sert au chrono.
    private(set) var firstFrames: [String: Date] = [:]
    /// Games dont Riot ne fournit pas les stats (404 sur `window`).
    private(set) var statsUnavailable: Set<String> = []
    /// Le dernier appel à l'API a échoué : bandeau « lolesports ne répond pas ».
    private(set) var isFailing = false
    /// Heure de DÉBUT de la dernière tentative réussie de chaque donnée (pas l'heure de la réponse : la cadence du
    /// direct, 60 s, se compte de début de requête à début de requête).
    private(set) var lastSuccess: [DataKind: Date] = [:]

    // MARK: Interne

    private let client: LoLClient
    private let transport: any HTTPTransport
    private let files: FileStore?
    private let isPreview: Bool
    /// Recharger les widgets quand les équipes suivies changent (jamais en aperçu ni dans les tests hébergés).
    private let reloadsWidgets: Bool
    @ObservationIgnored private var lastAttempt: [DataKind: Date] = [:]
    @ObservationIgnored private var scheduleLeagueIds: [String]? = nil
    @ObservationIgnored private var matchLeftLive = false
    @ObservationIgnored private var colorsDirty = true
    @ObservationIgnored private var isRefreshing = false
    /// `follows.json` / `settings.json` existent mais n'ont pas pu être lus au lancement (erreur d'E/S, par exemple
    /// fichier verrouillé) : les valeurs par défaut ne doivent jamais être écrites par-dessus. Avant la première
    /// modification de l'utilisateur, on retente la lecture.
    @ObservationIgnored private var followsUnreadable = false
    @ObservationIgnored private var settingsUnreadable = false

    private static let log = Logger(subsystem: "Faille", category: "données")

    init(transport: any HTTPTransport = URLSessionTransport(), files: FileStore) {
        self.transport = transport
        client = LoLClient(transport: transport)
        self.files = files
        isPreview = false
        reloadsWidgets = !RunEnvironment.isTesting
        loadFromDisk(files)
    }

    /// Store figé pour les #Preview et les tests d'aperçu : aucune requête, aucun fichier.
    init(preview data: PreviewData) {
        let previewTransport = URLSessionTransport()
        transport = previewTransport
        client = LoLClient(transport: previewTransport)
        files = nil
        isPreview = true
        reloadsWidgets = false
        follows = data.follows
        settings = data.settings
        leagues = data.leagues
        catalog = data.catalog
        schedule = data.schedule
        live = data.live
        details = data.details
        snapshots = data.snapshots
        snapshotDates = data.snapshots.mapValues { _ in Date() }
        firstFrames = data.firstFrames
        statsUnavailable = data.statsUnavailable
        isFailing = data.isFailing
        if let update = data.lastUpdate {
            lastSuccess = [.schedule: update, .live: update]
        }
        recomputeDirectory()
    }

    private func loadFromDisk(_ files: FileStore) {
        if let saved = files.load(FollowList.self, from: .follows) {
            follows = saved
        } else {
            followsUnreadable = Self.exists(.follows, in: files)
        }
        if let saved = files.load(AppSettings.self, from: .settings) {
            settings = saved
        } else {
            settingsUnreadable = Self.exists(.settings, in: files)
        }
        if let cached = files.load(Cached<[League]>.self, from: .leagues) {
            leagues = cached.value
            lastSuccess[.leagues] = cached.fetchedAt
        }
        if let cached = files.load(Cached<[Team]>.self, from: .teams) {
            catalog = cached.value
            lastSuccess[.teams] = cached.fetchedAt
        }
        if let cached = files.load(Cached<SchedulePage>.self, from: .schedule) {
            schedule = cached.value.events
            scheduleLeagueIds = cached.value.leagueIds
            lastSuccess[.schedule] = cached.fetchedAt
        }
        let cachedLive = files.load(Cached<[MatchEvent]>.self, from: .live)
        live = RefreshPolicy.usableLive(cachedLive, now: Date())
        if live != nil {
            lastSuccess[.live] = cachedLive?.fetchedAt
        }
        recomputeDirectory()
    }

    /// Le fichier est là (même s'il n'a pas pu être lu) : `load` renvoie aussi nil pour un fichier absent.
    private static func exists(_ file: FileStore.File, in files: FileStore) -> Bool {
        FileManager.default.fileExists(atPath: files.url(file).path(percentEncoded: false))
    }

    // MARK: Lectures pour les vues

    /// Cartes Vitrail de l'onglet Matchs : en direct d'abord, puis par prochain match (spec §5.1). Une carte dont la
    /// ligne « Prochain » est masquée (spec §8) n'est pas ordonnée par son prochain match.
    var cards: [TeamCard] {
        TeamCards.build(follows: follows, schedule: schedule, live: live, revealed: settings.revealedMatchIds)
    }

    /// Ligne « Prochain » d'une carte : `.hidden` tant que le dernier match de l'équipe est masqué (spec §8, jamais
    /// `card.next` directement : l'existence ou l'adversaire du prochain match trahirait un résultat).
    func nextLine(for card: TeamCard) -> NextLine {
        Presenter.nextLine(for: card, follows: follows, revealed: settings.revealedMatchIds)
    }

    /// Sous-titre de l'onglet Matchs ; les cartes à « Prochain » masqué ne comptent pas dans « à venir ».
    func cardsSubtitle(_ cards: [TeamCard]) -> String {
        Format.cardsSubtitle(cards, follows: follows, revealed: settings.revealedMatchIds)
    }

    /// Dernière mise à jour réussie du calendrier ou du direct.
    var lastUpdate: Date? {
        [lastSuccess[.schedule], lastSuccess[.live]].compactMap { $0 }.max()
    }

    /// Texte du bandeau d'erreur ; nil quand l'API répond (spec §10).
    var bannerText: String? {
        isFailing ? Format.offlineBanner(lastUpdate: lastUpdate) : nil
    }

    /// Un match par id : le direct fait foi, sinon le calendrier.
    func event(id: String) -> MatchEvent? {
        live?.first(where: { $0.id == id }) ?? schedule.first(where: { $0.id == id })
    }

    /// L'équipe suivie qui correspond à cette équipe d'un match (id, nom, logo ; jamais le code seul).
    func followed(_ team: MatchTeam) -> FollowedTeam? {
        follows.teams.first { team.isSame(as: $0) }
    }

    func isMasked(_ teams: [MatchTeam], matchId: String) -> Bool {
        SpoilerPolicy.isMasked(teams, matchId: matchId, follows: follows, revealed: settings.revealedMatchIds)
    }

    func scoreLine(_ event: MatchEvent) -> ScoreLine {
        Presenter.scoreLine(for: event, follows: follows, revealed: settings.revealedMatchIds)
    }

    /// État d'un match en direct pour sa carte : anti-spoiler, phase, score, chrono et stats viennent de LoLKit.
    func liveState(for event: MatchEvent) -> LiveMatchState {
        state(details: EventDetails(event: event), statsDisabled: event.statsDisabled)
    }

    /// Même chose depuis `getEventDetails` (écran Détail) ; nil tant que les détails ne sont pas chargés.
    func detailState(matchId: String) -> LiveMatchState? {
        guard let loaded = self.details[matchId] else { return nil }
        return state(details: loaded, statsDisabled: loaded.statsDisabled || event(id: matchId)?.statsDisabled == true)
    }

    private func state(details: EventDetails, statsDisabled: Bool) -> LiveMatchState {
        let game = details.currentGame
        let unavailable = game.map { statsUnavailable.contains($0.id) } ?? false
        return LiveMatchBuilder.state(
            details: details,
            snapshot: game.flatMap { snapshots[$0.id] },
            firstFrameTime: game.flatMap { firstFrames[$0.id] },
            statsDisabled: statsDisabled || unavailable,
            follows: follows,
            revealed: settings.revealedMatchIds,
            // Heure de réception de la frame : le chrono démarre au bon endroit et tourne ensuite tout seul.
            now: game.flatMap { snapshotDates[$0.id] } ?? Date()
        )
    }

    func teams(in league: League) -> [Team] {
        TeamDirectory.teams(in: league, catalog: catalog, schedule: schedule)
    }

    func search(_ query: String) -> [Team] {
        TeamDirectory.search(query, in: catalog)
    }

    /// Fichier du logo en cache (miniature PNG), s'il a déjà été téléchargé.
    /// `image` est la chaîne BRUTE de l'API (`Team.image`, `MatchTeam.image`, `FollowedTeam.image`), jamais l'URL
    /// convertie en https : c'est elle qui donne le nom du fichier (`LogoFileName`).
    func logoFile(for image: String?) -> URL? {
        guard let image, let files else { return nil }
        let name = LogoFileName.name(for: image)
        return files.hasLogo(named: name) ? files.logoURL(named: name) : nil
    }

    // MARK: Actions de l'utilisateur

    /// Étoile d'une équipe du catalogue : suivre ou ne plus suivre.
    func toggleFollow(_ team: Team) {
        syncFollowsBeforeChange()
        if follows.contains(id: team.id) {
            follows.unfollow(id: team.id)
        } else {
            follows.follow(team)
            colorsDirty = true
        }
        saveFollows()
        // Une équipe d'une autre ligue change les ligues du calendrier : la politique le voit tout de suite.
        Task { await refreshDue(opening: false) }
    }

    func unfollow(id: String) {
        syncFollowsBeforeChange()
        follows.unfollow(id: id)
        saveFollows()
    }

    /// Œil d'une équipe suivie (spec §8).
    func setSpoilerFree(_ on: Bool, id: String) {
        syncFollowsBeforeChange()
        follows.setSpoilerFree(on, id: id)
        saveFollows()
        Task { await refreshLiveStats() }
    }

    /// Couleur choisie à la main ; nil = revenir à la couleur tirée du logo.
    func setColorOverride(_ hex: String?, id: String) {
        syncFollowsBeforeChange()
        follows.setColorOverride(hex, id: id)
        saveFollows()
    }

    /// « Toucher pour révéler » (spec §8) : mémorisé pour ce match, sur toutes les surfaces.
    func reveal(matchId: String) {
        syncSettingsBeforeChange()
        settings.revealedMatchIds.insert(matchId)
        saveSettings()
        Task { await refreshLiveStats() }
    }

    /// Réglage « Live Activity » (spec §5.4), utilisé à l'étape 4.
    func setLiveActivityMode(_ mode: LiveActivityMode) {
        syncSettingsBeforeChange()
        settings.liveActivityMode = mode
        saveSettings()
    }

    // MARK: Rafraîchissements

    /// Boucle du premier plan, lancée par `.task(id: scenePhase)` : s'arrête, requêtes comprises, quand la tâche est annulée.
    func poll() async {
        var opening = true
        while !Task.isCancelled {
            await refreshDue(opening: opening)
            opening = false
            try? await Task.sleep(for: .seconds(RefreshPolicy.tick))
        }
    }

    /// Tirer pour rafraîchir : calendrier et direct relus, comme à l'ouverture, même juste après un échec ; les
    /// données qui n'ont encore jamais réussi (premier lancement hors ligne) aussi. Ne rend la main qu'une fois ses
    /// requêtes faites (le spinner de `.refreshable` en dépend), y compris quand un cycle était déjà en cours.
    func refreshNow() async {
        await cycle(opening: true, pullToRefresh: true)
    }

    /// Un cycle : ce que `RefreshPolicy` juge dû, dans l'ordre ligues → équipes → direct → calendrier.
    func refreshDue(opening: Bool) async {
        await cycle(opening: opening, pullToRefresh: false)
    }

    /// Une demande de rafraîchissement n'est jamais perdue : si un cycle tourne déjà (la boucle, ou celui lancé par un
    /// `toggleFollow`), on attend sa fin puis on fait le sien, avec sa propre ouverture / son propre forçage.
    /// - Parameter pullToRefresh: oublie la dernière tentative du direct, du calendrier et de toute donnée qui n'a
    ///   jamais réussi, avant de consulter la politique, pour qu'un tirer-pour-rafraîchir agisse même dans la minute
    ///   qui suit un échec (le délai de nouvel essai ne le retient pas).
    private func cycle(opening: Bool, pullToRefresh: Bool) async {
        guard !isPreview else { return }
        while isRefreshing {
            // Attente courte et annulable : la tâche qui attend s'arrête avec sa scène.
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
        }
        isRefreshing = true
        defer { isRefreshing = false }
        if pullToRefresh {
            for kind in DataKind.allCases where kind == .live || kind == .schedule || lastSuccess[kind] == nil {
                lastAttempt[kind] = nil
            }
        }
        let due = RefreshPolicy.due(refreshInput(opening: opening))
        var liveFetched = false
        for kind in [DataKind.leagues, .teams, .live] where due.contains(kind) {
            let succeeded = await fetch(kind)
            if Task.isCancelled { return }
            if kind == .live { liveFetched = succeeded }
        }
        // Le calendrier dépend des ligues (peut-être tout juste chargées) et des matchs sortis du direct : on redemande.
        if RefreshPolicy.due(refreshInput(opening: opening)).contains(.schedule) {
            await fetch(.schedule)
            if Task.isCancelled { return }
        }
        // Un direct qui vient d'échouer n'est pas une raison de demander les stats de ses matchs (ils échoueraient aussi).
        if liveFetched { await refreshLiveStats() }
        if colorsDirty && !isFailing && !Task.isCancelled { await updateTeamColors() }
    }

    private var wantedLeagueIds: [String] {
        ScheduleQuery.leagueIds(follows: follows, leagues: leagues)
    }

    private func refreshInput(opening: Bool) -> RefreshInput {
        RefreshInput(now: Date(), opening: opening, lastSuccess: lastSuccess, lastAttempt: lastAttempt,
                     scheduleLeagueIds: scheduleLeagueIds, wantedLeagueIds: wantedLeagueIds, matchLeftLive: matchLeftLive)
    }

    /// Une requête annulée (passage en arrière-plan, sortie de l'écran Détail) n'est pas une panne : avec le vrai
    /// réseau elle remonte en `URLError(.cancelled)`, dans les tests en `CancellationError`.
    private nonisolated static func isCancellation(_ error: any Error) -> Bool {
        Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    /// - Returns: vrai si la donnée a été relue ; faux en cas d'échec ou d'annulation.
    @discardableResult
    private func fetch(_ kind: DataKind) async -> Bool {
        let started = Date()
        let previousAttempt = lastAttempt[kind]
        lastAttempt[kind] = started
        do {
            switch kind {
            case .leagues:
                let value = try await client.leagues()
                leagues = value
                files?.save(Cached(value: value, fetchedAt: started), to: .leagues)
            case .teams:
                let value = try await client.teams()
                catalog = value
                let before = follows
                follows.refresh(from: value) // renommages de sponsor, nouveaux logos
                persistFollowsIfChanged(from: before)
                colorsDirty = true
                files?.save(Cached(value: value, fetchedAt: started), to: .teams)
            case .schedule:
                let ids = wantedLeagueIds
                let events = try await client.schedule(leagueIds: ids)
                schedule = events
                scheduleLeagueIds = ids
                matchLeftLive = false
                files?.save(Cached(value: SchedulePage(leagueIds: ids, events: events), fetchedAt: started), to: .schedule)
            case .live:
                let events = try await client.live()
                if RefreshPolicy.leftLive(previous: live, current: events) {
                    matchLeftLive = true // spec §10 : relire getSchedule aussitôt
                }
                live = events
                files?.save(Cached(value: events, fetchedAt: started), to: .live)
            }
            lastSuccess[kind] = started
            isFailing = false
            if kind != .live { recomputeDirectory() }
            return true
        } catch {
            if Self.isCancellation(error) {
                // Passage en arrière-plan : ce n'est pas une panne (ni tentative ratée ni bandeau), on réessaiera
                // à la prochaine ouverture.
                lastAttempt[kind] = previousAttempt
                return false
            }
            isFailing = true
            Self.log.error("\(kind.rawValue, privacy: .public) : \(String(describing: error), privacy: .public)")
            if let apiError = error as? LoLAPIError, apiError == .http(status: 403) {
                Self.log.fault("403 sur persisted/gw : la clé publique a sans doute changé (LoLClient.publicAPIKey)")
            }
            if kind == .live, let success = lastSuccess[.live], Date().timeIntervalSince(success) > RefreshPolicy.liveTrust {
                live = nil // direct trop vieux : les cartes retombent sur le calendrier
            }
            return false
        }
    }

    /// Stats des matchs en direct des équipes suivies, pour leurs cartes (cadence du direct). Les matchs masqués ne
    /// sont pas demandés. Une game en cours est interrogée même quand Riot n'en fournit pas les stats
    /// (`statsDisabled`) : le chrono (spec §4.3, §5.1) n'en dépend pas, et les stats restent cachées par LoLKit.
    /// Un 404 arrête ensuite les nouvelles tentatives pour cette game (`statsUnavailable`).
    func refreshLiveStats() async {
        guard !isPreview, let live else { return }
        for event in live where follows.involves(event.match.teams) {
            if Task.isCancelled { return }
            guard !isMasked(event.match.teams, matchId: event.id),
                  let game = EventDetails(event: event).currentGame else { continue }
            await loadWindow(gameId: game.id, inProgress: true)
        }
    }

    /// Dernière frame d'une game ; pour une game en cours, aussi sa première frame (chrono), une seule fois.
    /// Pour une game terminée, `startingTime` récent renvoie les dernières frames de la game.
    func loadWindow(gameId: String, inProgress: Bool) async {
        guard !isPreview, !statsUnavailable.contains(gameId) else { return }
        do {
            if inProgress && firstFrames[gameId] == nil {
                firstFrames[gameId] = try await client.window(gameId: gameId, startingTime: nil).firstFrameTime
            }
            let fetchedAt = Date()
            let window = try await client.window(gameId: gameId, startingTime: LiveStatsTime.startingTime(now: fetchedAt))
            if let snapshot = window.latestSnapshot() {
                snapshots[gameId] = snapshot
                snapshotDates[gameId] = fetchedAt
            }
        } catch LoLAPIError.statsDisabled {
            statsUnavailable.insert(gameId)
        } catch {
            // Flux vide (game pas commencée), réseau : on garde la dernière frame connue.
            if !Self.isCancellation(error) {
                Self.log.info("window \(gameId, privacy: .public) : \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// `getEventDetails` d'un match (écran Détail).
    func loadDetails(matchId: String) async {
        guard !isPreview else { return }
        do {
            details[matchId] = try await client.eventDetails(matchId: matchId)
        } catch {
            if !Self.isCancellation(error) {
                Self.log.info("détails \(matchId, privacy: .public) : \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Couleur automatique de chaque équipe suivie, tirée de son logo (spec §9) ; refaite quand le logo change d'URL.
    /// Le nom du fichier vient de la chaîne brute de l'API ; l'URL https ne sert qu'au téléchargement.
    ///
    /// `colorsDirty` ne redevient vrai que par un rafraîchissement des équipes (une fois par jour), un nouvel abonnement,
    /// ou une passe interrompue par une annulation. Un logo qui échoue (réseau, hôte des images en panne) est donc
    /// sauté sans bloquer les équipes suivantes, et n'est réessayé qu'au prochain rafraîchissement des équipes : pas
    /// de tempête de requêtes à chaque tick.
    private func updateTeamColors() async {
        colorsDirty = false
        guard let files else { return }
        let before = follows
        defer { persistFollowsIfChanged(from: before) }
        for team in before.teams {
            guard let image = team.image, let url = ImageURL.secure(image) else { continue }
            let name = LogoFileName.name(for: image)
            if team.autoColorHex != nil && files.hasLogo(named: name) { continue }
            do {
                let response = try await transport.get(url, headers: [:])
                guard response.status == 200, let thumbnail = LogoPixels.thumbnail(from: response.body) else {
                    // Logo absent ou illisible (SVG…) : accent, pour ne pas le retélécharger à chaque cycle.
                    follows.setAutoColor(RGB.accent.hex, id: team.id)
                    continue
                }
                if let png = LogoPixels.png(thumbnail) {
                    files.saveLogo(png, named: name)
                }
                let color = LogoPixels.rgba(thumbnail).map { TeamColor.teamColor(rgba: TeamColor.unpremultiplied($0)) } ?? .accent
                follows.setAutoColor(color.hex, id: team.id)
            } catch {
                if Self.isCancellation(error) {
                    // Passe interrompue (scène en arrière-plan) : on la refera au prochain cycle.
                    colorsDirty = true
                    break
                }
                // Ce logo seul est en échec : on passe aux équipes suivantes.
                Self.log.info("logo de \(team.code, privacy: .public) : \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func recomputeDirectory() {
        leaguePills = TeamDirectory.leagues(leagues, catalog: catalog, schedule: schedule)
    }

    // MARK: Enregistrement

    /// Avant chaque modification de l'utilisateur : si `follows.json` n'avait pas pu être lu au lancement, on retente,
    /// pour ne pas écraser la vraie liste par une liste réduite à la seule modification. Le drapeau « illisible » ne
    /// tombe qu'après une relecture réussie, ou si le fichier n'existe plus (mis de côté par `load`, supprimé) ; sinon
    /// la modification reste en mémoire et `saveFollows` n'écrit rien (le fichier d'origine reste intact).
    private func syncFollowsBeforeChange() {
        guard followsUnreadable, let files else { return }
        if let saved = files.load(FollowList.self, from: .follows) {
            follows = saved
            followsUnreadable = false
        } else if !Self.exists(.follows, in: files) {
            followsUnreadable = false
        } else {
            Self.log.error("follows.json toujours illisible : la modification reste en mémoire, le fichier n'est pas écrasé")
        }
    }

    /// Même règle pour `settings.json`.
    private func syncSettingsBeforeChange() {
        guard settingsUnreadable, let files else { return }
        if let saved = files.load(AppSettings.self, from: .settings) {
            settings = saved
            settingsUnreadable = false
        } else if !Self.exists(.settings, in: files) {
            settingsUnreadable = false
        } else {
            Self.log.error("settings.json toujours illisible : la modification reste en mémoire, le fichier n'est pas écrasé")
        }
    }

    /// Écriture voulue par l'utilisateur (suivre, masquer, couleur…) : enregistre, puis prévient les widgets.
    /// Rien n'est écrit tant que le fichier existant n'a pas pu être relu (il ne doit jamais être écrasé).
    private func saveFollows() {
        guard !followsUnreadable else { return }
        files?.save(follows, to: .follows)
        if reloadsWidgets {
            // Le widget (sonde, puis les vrais à l'étape 3) relit les équipes suivies tout de suite.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Écriture déclenchée par un rafraîchissement (renommage d'équipe, couleur du logo) : seulement si la liste a
    /// vraiment changé, et jamais tant que le fichier d'origine n'a pas pu être lu (une liste vide par défaut ne
    /// doit pas l'écraser).
    private func persistFollowsIfChanged(from before: FollowList) {
        guard follows != before, !followsUnreadable else { return }
        saveFollows()
    }

    private func saveSettings() {
        guard !settingsUnreadable else { return }
        files?.save(settings, to: .settings)
    }
}
