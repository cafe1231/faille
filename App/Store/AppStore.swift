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
    /// iOS a refusé les notifications demandées par l'interrupteur d'une ligue (`setLeagueNotifications`) : la note des
    /// Réglages (« Notifications refusées par iOS… ») s'affiche sous l'interrupteur.
    private(set) var leagueNotificationsDenied = false
    /// Heure de DÉBUT de la dernière tentative réussie de chaque donnée (pas l'heure de la réponse : la cadence du
    /// direct, 60 s, se compte de début de requête à début de requête).
    private(set) var lastSuccess: [DataKind: Date] = [:]
    /// Live Activities (spec §6) : tous les appels à ActivityKit passent par lui.
    let liveActivities: LiveActivityController
    /// Réveils d'arrière-plan reçus et demandés (bloc « Diagnostic Live Activity » de À propos) ; enregistré, car iOS
    /// relance l'appli pour un réveil et la mémoire du processus ne survit pas jusqu'à la prochaine ouverture.
    private(set) var backgroundDiagnostic = BackgroundDiagnostic()
    /// Fonctionnalités (spec fonctionnalités §3-§5) : images et données Data Dragon, détails par joueur, fil et courbe de
    /// gold, sorts d'invocateur — chacun avec son cache disque sous `cache/`, tous inertes dans les aperçus. Jamais
    /// sollicités pour un match masqué (`MatchDetailModel.featureGame`).
    let dataDragon: DataDragonStore
    let gameDetails: GameDetailsStore
    let timelines: TimelineStore
    let summonerSpells: SummonerSpellsStore
    /// Statistiques de saison (spec saison §1) : games lues, tournois, classements, et leur collecte au premier plan
    /// (`seasonLoop`). Inerte dans les aperçus.
    let season: SeasonStore
    /// Notifications de début de match (spec fonctionnalités §2) : `UNUserNotificationCenter` dans l'appli, inerte dans
    /// les aperçus et les tests hébergés.
    let reminderCenter: any ReminderCenter
    /// Patch du flux de chaque game lue (`gameMetadata.patchVersion`) : il donne la version Data Dragon de ses images.
    private(set) var patches: [String: String] = [:]

    // MARK: Interne

    private let client: LoLClient
    private let transport: any HTTPTransport
    private let files: FileStore?
    private let isPreview: Bool
    /// Appeler WidgetKit pour recharger les widgets (jamais en aperçu ni dans les tests hébergés).
    private let reloadsWidgets: Bool
    @ObservationIgnored private var lastAttempt: [DataKind: Date] = [:]
    @ObservationIgnored private var scheduleLeagueIds: [String]? = nil
    @ObservationIgnored private var matchLeftLive = false
    @ObservationIgnored private var colorsDirty = true
    @ObservationIgnored private var isRefreshing = false
    /// Tâches lancées par une action de l'utilisateur (suivre, masquer, révéler, épingler…) : elles vivent avec la scène
    /// et sont annulées quand la boucle du premier plan s'arrête (`endScene`), au lieu de continuer en arrière-plan.
    @ObservationIgnored private var sceneTasks: [UUID: Task<Void, Never>] = [:]
    /// Un vrai passage en arrière-plan a eu lieu : la prochaine boucle de collecte repart d'un budget neuf (I-2).
    @ObservationIgnored var seasonSessionPending = false
    /// `follows.json` / `settings.json` existent mais n'ont pas pu être lus au lancement (erreur d'E/S, par exemple
    /// fichier verrouillé) : les valeurs par défaut ne doivent jamais être écrites par-dessus. Avant la première
    /// modification de l'utilisateur, on retente la lecture. `followsUnreadable` est aussi lu par `syncLiveActivities`, et
    /// les deux par `syncReminders` (autres fichiers, d'où `private(set)`).
    @ObservationIgnored private(set) var followsUnreadable = false
    @ObservationIgnored private(set) var settingsUnreadable = false
    /// Demandes de rechargement des widgets (lu par les tests ; WidgetKit n'est appelé que si `reloadsWidgets`).
    @ObservationIgnored private(set) var widgetReloadRequests = 0

    private static let log = Logger(subsystem: "Faille", category: "données")

    /// - Parameters:
    ///   - liveActivities: contrôleur des Live Activities ; nil (l'appli) : celui du dossier `files`. Les tests en passent
    ///     un (aperçu) pour simuler des Live Activities à l'écran.
    ///   - reminderCenter: centre des notifications ; nil : celui d'iOS (inerte dans les tests hébergés).
    init(transport: any HTTPTransport = URLSessionTransport(), files: FileStore,
         liveActivities: LiveActivityController? = nil, reminderCenter: (any ReminderCenter)? = nil) {
        self.transport = transport
        client = LoLClient(transport: transport)
        self.files = files
        isPreview = false
        reloadsWidgets = !RunEnvironment.isTesting
        // Tests hébergés : aucune Live Activity réelle (les choix restent enregistrés et testables).
        self.liveActivities = liveActivities
            ?? LiveActivityController(files: files, usesActivityKit: !RunEnvironment.isTesting)
        // Caches des fonctionnalités : `cache/` à côté des fichiers de Faille (exclu de la sauvegarde iCloud).
        let cache = DiskCache(root: files.directory.appendingPathComponent("cache", isDirectory: true))
        dataDragon = DataDragonStore(transport: transport, cache: cache)
        gameDetails = GameDetailsStore(transport: transport, cache: cache)
        timelines = TimelineStore(transport: transport, cache: cache)
        summonerSpells = SummonerSpellsStore(transport: transport, cache: cache)
        season = SeasonStore(transport: transport, cache: cache)
        if let reminderCenter {
            self.reminderCenter = reminderCenter
        } else if RunEnvironment.isTesting {
            self.reminderCenter = InertReminderCenter()
        } else {
            self.reminderCenter = SystemReminderCenter()
        }
        loadFromDisk(files)
        markOnboardedIfExistingUser()
        // Le disque de la saison est lu par `seasonLoop`, au premier plan (M8) : pas à l'init.
    }

    /// Store figé pour les #Preview et les tests d'aperçu : aucune requête, aucun fichier.
    init(preview data: PreviewData) {
        let previewTransport = URLSessionTransport()
        transport = previewTransport
        client = LoLClient(transport: previewTransport)
        files = nil
        isPreview = true
        reloadsWidgets = false
        liveActivities = LiveActivityController(preview: data.activityMatchIds)
        // Fonctionnalités figées (`FeatureSamples`) : aucune requête, aucun fichier, aucune notification.
        dataDragon = DataDragonStore.preview()
        gameDetails = GameDetailsStore(preview: FeatureSamples.details)
        timelines = TimelineStore(preview: FeatureSamples.timelines)
        summonerSpells = SummonerSpellsStore(preview: FeatureSamples.spells)
        season = SeasonStore(preview: AppStore.seasonPreview(data.season))
        reminderCenter = InertReminderCenter()
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
        backgroundDiagnostic = files.load(BackgroundDiagnostic.self, from: .backgroundDiagnostic) ?? BackgroundDiagnostic()
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

    /// Ligne « Prochain » d'une carte : `.hidden` tant que le dernier match de l'équipe est masqué, ou que son prochain
    /// match l'oppose à une autre équipe suivie en anti-spoiler dont le dernier match est masqué (spec §8, règle C ;
    /// jamais `card.next` directement : l'existence ou l'adversaire du prochain match trahirait un résultat). La règle C
    /// se juge sur toutes les cartes de l'écran.
    func nextLine(for card: TeamCard) -> NextLine {
        let revealed = settings.revealedMatchIds
        return Presenter.nextLine(for: card, follows: follows, revealed: revealed,
                                  maskedLatestTeamIds: Presenter.maskedLatestTeamIds(cards, follows: follows,
                                                                                     revealed: revealed))
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
        state(details: EventDetails(event: event), statsDisabled: event.statsDisabled, updatedAt: lastSuccess[.live])
    }

    /// Même chose depuis `getEventDetails` (écran Détail) ; nil tant que les détails ne sont pas chargés.
    func detailState(matchId: String) -> LiveMatchState? {
        guard let loaded = self.details[matchId] else { return nil }
        return state(details: loaded, statsDisabled: loaded.statsDisabled || event(id: matchId)?.statsDisabled == true,
                     updatedAt: lastSuccess[.live])
    }

    /// État d'un match par LoLKit. Deux heures distinctes (spec §4.3) : l'heure de réception de la frame, ancre du
    /// chrono ; et `updatedAt`, dernière relecture réussie de la donnée (le direct, ou le calendrier), dont découle
    /// `staleDate` (nil : l'heure du calcul).
    func state(details: EventDetails, statsDisabled: Bool, updatedAt: Date?) -> LiveMatchState {
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
            now: game.flatMap { snapshotDates[$0.id] } ?? Date(),
            updatedAt: updatedAt
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
        season.wake()
        // Une équipe d'une autre ligue change les ligues du calendrier : la politique le voit tout de suite.
        runWithScene {
            await self.refreshDue(opening: false)
            guard !Task.isCancelled else { return }
            await self.syncLiveActivities(canStart: true)
        }
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
        runWithScene { await self.refreshActivitiesAfterSpoilerChange() }
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
        // Un match révélé devient éligible à la collecte (spec saison §1.6).
        season.wake()
        runWithScene { await self.refreshActivitiesAfterSpoilerChange() }
    }

    /// Réglage « Live Activity » (spec §5.4) : en manuel, les Live Activities non épinglées s'en vont tout de suite ;
    /// en automatique, celles des équipes suivies démarrent.
    func setLiveActivityMode(_ mode: LiveActivityMode) {
        syncSettingsBeforeChange()
        settings.liveActivityMode = mode
        saveSettings()
        runWithScene { await self.syncLiveActivities(canStart: true) }
    }

    /// Réglage « Notifications de début de match » (spec fonctionnalités §2) : enregistré tout de suite ; la
    /// reprogrammation suit d'elle-même (`reminderSignature` change, la scène relance `syncReminders`).
    func setMatchReminders(enabled: Bool) {
        syncSettingsBeforeChange()
        settings.matchRemindersEnabled = enabled
        saveSettings()
    }

    /// Délai des notifications de début de match : 5, 15 ou 30 min (`MatchReminders.leadOptions`).
    func setMatchReminderLead(_ lead: TimeInterval) {
        syncSettingsBeforeChange()
        settings.matchReminderLead = lead
        saveSettings()
    }

    /// Suivre une ligue, ou ne plus la suivre (spec saison §3.5) : son calendrier, sa collecte (priorité 3) et, si
    /// demandé, les notifications de début de ses matchs suivent.
    func toggleFollowLeague(_ league: League) {
        syncFollowsBeforeChange()
        if follows.containsLeague(id: league.id) {
            follows.unfollowLeague(id: league.id)
        } else {
            follows.follow(league: league)
        }
        saveFollows()
        season.wake()
        runWithScene { await self.refreshDue(opening: false) }
    }

    /// « Suivre ses N équipes » (spec saison §3.5) : toutes les équipes de la ligue (`TeamDirectory`), d'un coup.
    func followAllTeams(in league: League) {
        syncFollowsBeforeChange()
        for team in teams(in: league) where !follows.contains(id: team.id) {
            follows.follow(team)
        }
        colorsDirty = true
        saveFollows()
        season.wake()
        runWithScene {
            await self.refreshDue(opening: false)
            guard !Task.isCancelled else { return }
            await self.syncLiveActivities(canStart: true)
        }
    }

    /// Demande l'autorisation d'iOS pour les notifications de début de match : un seul chemin pour les Réglages
    /// (`MatchRemindersSection`) et pour les ligues. La première fois seulement iOS la demande ; refusée, `enabled` est
    /// faux et `denied` vrai.
    func requestReminderAuthorization() async -> MatchRemindersFlow.Outcome {
        await MatchRemindersFlow.toggle(to: true, center: reminderCenter)
    }

    /// Notifications de début des matchs d'une ligue suivie (spec saison §3.5, désactivées par défaut). L'activer allume
    /// aussi le réglage global (`matchRemindersEnabled`, sans lequel rien ne part) et demande l'autorisation d'iOS par le
    /// même chemin que les Réglages ; refusée, l'interrupteur de la ligue (et le réglage global, s'il vient d'être allumé
    /// ici) revient à faux et `leagueNotificationsDenied` porte la note.
    func setLeagueNotifications(_ on: Bool, leagueId: String) {
        syncFollowsBeforeChange()
        follows.setNotifyStarts(on, leagueId: leagueId)
        saveFollows()
        guard on else { return }
        leagueNotificationsDenied = false
        let enabledBefore = settings.matchRemindersEnabled
        if !enabledBefore {
            setMatchReminders(enabled: true)
        }
        runWithScene {
            let outcome = await self.requestReminderAuthorization()
            guard outcome.enabled != true, !Task.isCancelled else { return }
            self.syncFollowsBeforeChange()
            self.follows.setNotifyStarts(false, leagueId: leagueId)
            self.saveFollows()
            if !enabledBefore, !self.follows.leagues.contains(where: \.notifyStarts) {
                self.setMatchReminders(enabled: false)
            }
            self.leagueNotificationsDenied = true
        }
    }

    /// « Classement masqué · toucher pour révéler » (spec saison §3.5) : mémorisé par tournoi ; ne révèle aucun match.
    func revealStandings(tournamentId: String) {
        syncSettingsBeforeChange()
        settings.revealedStandingIds.insert(tournamentId)
        saveSettings()
    }

    /// Fin du premier lancement (« C'est parti » ou « Passer », spec saison §3.7).
    func completeOnboarding() {
        syncSettingsBeforeChange()
        settings.onboardingDone = true
        saveSettings()
    }

    /// Un utilisateur qui suit déjà des équipes au lancement (version précédente) est marqué « fait » sans voir
    /// l'onboarding (spec saison §3.7). Jamais tant que les réglages sont illisibles (ils ne doivent pas être écrasés).
    private func markOnboardedIfExistingUser() {
        guard !settings.onboardingDone, !follows.teams.isEmpty, !settingsUnreadable else { return }
        settings.onboardingDone = true
        files?.save(settings, to: .settings)
    }

    // MARK: Rafraîchissements

    /// Boucle du premier plan, lancée par `.task(id: scenePhase)` : s'arrête, requêtes comprises, quand la tâche est
    /// annulée. Deux boucles en parallèle : les données de l'API, et les couleurs tirées des logos — hors du cycle gardé
    /// par `isRefreshing`, un hôte de logos lent ne retient plus aucun rafraîchissement. Quand la scène quitte le premier
    /// plan, les tâches lancées par les actions de l'utilisateur s'arrêtent avec elle.
    func poll() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshLoop() }
            group.addTask { await self.colorLoop() }
            // Collecte des stats de saison (spec saison §1.6) : au premier plan seulement, arrêtée avec la scène.
            group.addTask { await self.seasonLoop() }
        }
        endScene()
    }

    private func refreshLoop() async {
        var opening = true
        while !Task.isCancelled {
            await refreshDue(opening: opening)
            opening = false
            // Une scène qui quitte le premier plan pendant le cycle ne démarre ni ne met à jour plus rien.
            guard !Task.isCancelled else { break }
            // Spec §6.4 : au premier plan, les Live Activities suivent chaque tour ; ActivityKit n'est appelé que si leur
            // contenu a changé (en pratique à chaque relecture du direct, 60 s).
            await syncLiveActivities(canStart: true)
            try? await Task.sleep(for: .seconds(RefreshPolicy.tick))
        }
    }

    /// Un tour d'attente d'abord : le premier cycle a alors dit si l'API répond (`isFailing`).
    private func colorLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(RefreshPolicy.tick))
            await updateColorsIfNeeded()
        }
    }

    /// Couleurs d'équipe à (re)calculer depuis les logos (spec §9) : au premier plan seulement, jamais pendant un réveil
    /// en arrière-plan (le temps accordé par iOS est compté), jamais quand l'API est en panne.
    func updateColorsIfNeeded() async {
        guard !isPreview, colorsDirty, !isFailing, !Task.isCancelled else { return }
        await updateTeamColors()
    }

    /// Lance le travail d'une action de l'utilisateur, lié à la scène (annulé par `endScene`).
    func runWithScene(_ work: @escaping @MainActor @Sendable () async -> Void) {
        let id = UUID()
        sceneTasks[id] = Task {
            await work()
            self.sceneTasks[id] = nil
        }
    }

    /// La scène quitte le premier plan : les tâches des actions s'arrêtent.
    func endScene() {
        for task in sceneTasks.values {
            task.cancel()
        }
        sceneTasks.removeAll()
    }

    /// Tâches d'action en cours (tests).
    var sceneTaskCount: Int {
        sceneTasks.count
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
        // Les widgets relisent le calendrier et le direct qui viennent d'être enregistrés (spec §7) : une fois par
        // cycle, et même si la tâche est annulée juste après un chargement réussi (le fichier est déjà écrit) : chaque
        // drapeau est donc levé AVANT le contrôle d'annulation qui suit la requête.
        var liveFetched = false
        var scheduleFetched = false
        defer { if liveFetched || scheduleFetched { reloadWidgets() } }
        if pullToRefresh {
            for kind in DataKind.allCases where kind == .live || kind == .schedule || lastSuccess[kind] == nil {
                lastAttempt[kind] = nil
            }
        }
        let due = RefreshPolicy.due(refreshInput(opening: opening))
        for kind in [DataKind.leagues, .teams, .live] where due.contains(kind) {
            let succeeded = await fetch(kind)
            if kind == .live { liveFetched = succeeded }
            if Task.isCancelled { return }
        }
        // Le calendrier dépend des ligues (peut-être tout juste chargées) et des matchs sortis du direct : on redemande.
        if RefreshPolicy.due(refreshInput(opening: opening)).contains(.schedule) {
            scheduleFetched = await fetch(.schedule)
            if Task.isCancelled { return }
        }
        // Stats des cartes à chaque tour (10 s) : le flux n'a une nouvelle donnée que toutes les 10 s, alors que le direct
        // reste relu toutes les 60 s (cache CloudFront de 60 s, spec §4.1). Pas de stats quand le direct vient d'échouer
        // (elles échoueraient aussi), quand l'API est en échec, ni sur un direct trop vieux pour être cru. Les détails des
        // Live Activities orphelines restent relus à la cadence du direct.
        let liveTrusted = lastSuccess[.live].map { Date().timeIntervalSince($0) <= RefreshPolicy.liveTrust } ?? false
        if liveFetched || (!due.contains(.live) && liveTrusted && !isFailing) {
            await refreshLiveStats(includingDetails: liveFetched)
        }
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

    /// Stats des matchs en direct des équipes suivies (cartes) et de ceux qui ont une Live Activity (match épinglé
    /// d'équipes non suivies), à chaque tour du premier plan (10 s). Les matchs masqués ne sont pas demandés. Une game en cours est
    /// interrogée même quand Riot n'en fournit pas les stats (`statsDisabled`) : le chrono (spec §4.3, §5.1) n'en
    /// dépend pas, et les stats restent cachées par LoLKit. Un 404 arrête ensuite les nouvelles tentatives pour cette
    /// game (`statsUnavailable`).
    /// Un match dont la Live Activity est à l'écran, sorti du direct et pas terminé au calendrier (compétition hors des
    /// ligues suivies, équipe plus suivie), est relu par ses détails : seuls eux disent que sa série est gagnée
    /// (`activityContent`).
    func refreshLiveStats(includingDetails: Bool = true) async {
        guard !isPreview, let live else { return }
        for event in live where follows.involves(event.match.teams) || liveActivities.shownMatchIds.contains(event.id) {
            if Task.isCancelled { return }
            guard !isMasked(event.match.teams, matchId: event.id),
                  let game = EventDetails(event: event).currentGame else { continue }
            await loadWindow(gameId: game.id, inProgress: true)
        }
        guard includingDetails else { return }
        for matchId in liveActivities.shownMatchIds where !live.contains(where: { $0.id == matchId })
            && schedule.first(where: { $0.id == matchId })?.state != .completed {
            if Task.isCancelled { return }
            await loadDetails(matchId: matchId)
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
            let window = try await client.liveWindow(gameId: gameId, now: fetchedAt)
            if let snapshot = window.latestSnapshot() {
                snapshots[gameId] = snapshot
                snapshotDates[gameId] = fetchedAt
            }
            if let patch = window.gameMetadata.patchVersion {
                patches[gameId] = patch
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

    // MARK: Diagnostic de l'arrière-plan

    /// Un réveil d'arrière-plan vient d'être reçu d'iOS (`BGAppRefreshTask`).
    func recordBackgroundWake(at date: Date = Date()) {
        backgroundDiagnostic.lastWake = date
        saveBackgroundDiagnostic()
    }

    /// Résultat de la dernière demande de réveil faite à iOS.
    func recordWakeRequest(_ outcome: WakeRequest.Outcome, at date: Date = Date()) {
        backgroundDiagnostic.lastRequest = WakeRequest(at: date, outcome: outcome)
        saveBackgroundDiagnostic()
    }

    private func saveBackgroundDiagnostic() {
        files?.save(backgroundDiagnostic, to: .backgroundDiagnostic)
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
        reloadWidgets()
    }

    /// Écriture déclenchée par un rafraîchissement (renommage d'équipe, couleur du logo) : seulement si la liste a
    /// vraiment changé, et jamais tant que le fichier d'origine n'a pas pu être lu (une liste vide par défaut ne
    /// doit pas l'écraser).
    private func persistFollowsIfChanged(from before: FollowList) {
        guard follows != before, !followsUnreadable else { return }
        saveFollows()
    }

    /// Réglages (mode Live Activity, matchs révélés) : une révélation se voit tout de suite dans les widgets (spec §8).
    private func saveSettings() {
        guard !settingsUnreadable else { return }
        files?.save(settings, to: .settings)
        reloadWidgets()
    }

    /// Les widgets relisent les fichiers du groupe d'apps (spec §7). Demandés au premier plan, ces rechargements ne
    /// sont pas décomptés du budget de WidgetKit : c'est l'appli ouverte, pas l'extension, qui les déclenche
    /// (`WidgetTimeline.reloadDate` ne redemande que 5 h plus tard). Les rechargements faits en arrière-plan (étape 4)
    /// compteront, eux, dans ce budget.
    private func reloadWidgets() {
        widgetReloadRequests += 1
        if reloadsWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
