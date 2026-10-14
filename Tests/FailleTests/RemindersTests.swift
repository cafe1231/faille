import Foundation
import LoLKit
import Testing
import UserNotifications
@testable import Faille

/// Faux centre de notifications : garde ce qui est programmé ; l'autorisation et la réponse à la demande se règlent.
actor FakeReminderCenter: ReminderCenter {
    private(set) var pending: [String: MatchReminder] = [:]
    /// Notifications d'une autre origine : elles ne doivent jamais être retirées.
    private(set) var foreign: Set<String>
    private(set) var status: ReminderAuthorization
    private let grants: Bool
    /// Identifiants que `add` refuse (comme iOS peut le faire) : la programmation doit continuer avec les autres.
    private let refusing: Set<String>
    private(set) var authorizationRequests = 0

    struct Refused: Error {}

    init(status: ReminderAuthorization = .authorized, grants: Bool = true, foreign: Set<String> = [],
         refusing: Set<String> = []) {
        self.status = status
        self.grants = grants
        self.foreign = foreign
        self.refusing = refusing
    }

    func authorization() async -> ReminderAuthorization { status }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        status = grants ? .authorized : .denied
        return grants
    }

    func pendingIdentifiers() async -> [String] { Array(pending.keys) + Array(foreign) }

    func remove(identifiers: [String]) async {
        for id in identifiers {
            pending[id] = nil
            foreign.remove(id)
        }
    }

    func add(_ reminder: MatchReminder) async throws {
        if refusing.contains(reminder.id) { throw Refused() }
        pending[reminder.id] = reminder
    }
}

/// Programmation des notifications de début de match (spec fonctionnalités §2) : remplacement de celles de Faille seules,
/// rien sans réglage ni autorisation, et l'id du match transporté pour ouvrir son Détail.
@MainActor
struct RemindersTests {
    private static func reminder(_ matchId: String, in minutes: Double) -> MatchReminder {
        MatchReminder(id: MatchReminders.identifier(matchId: matchId), matchId: matchId,
                      fireDate: Date().addingTimeInterval(minutes * 60), title: "KC vs G2 dans 15 min",
                      subtitle: "Mondial · Play-in · Bo5")
    }

    @Test func applyReplacesFailleRemindersOnly() async {
        let center = FakeReminderCenter(foreign: ["autre-appli"])
        await ReminderSync.apply([Self.reminder("old", in: 30)], enabled: true, center: center)
        await ReminderSync.apply([Self.reminder("m1", in: 60), Self.reminder("m2", in: 90)], enabled: true, center: center)
        #expect(Set(await center.pending.keys) == ["match-start-m1", "match-start-m2"])
        #expect(await center.foreign == ["autre-appli"])
    }

    @Test func switchedOffRemovesEveryFailleReminder() async {
        let center = FakeReminderCenter(foreign: ["autre-appli"])
        await ReminderSync.apply([Self.reminder("m1", in: 60)], enabled: true, center: center)
        await ReminderSync.apply([Self.reminder("m1", in: 60)], enabled: false, center: center)
        #expect(await center.pending.isEmpty)
        #expect(await center.foreign == ["autre-appli"])
    }

    /// Sans autorisation d'iOS, rien n'est programmé (et l'autorisation n'est jamais demandée ici : seulement par le
    /// réglage, quand on l'active).
    @Test func withoutAuthorizationNothingIsScheduled() async {
        for status in [ReminderAuthorization.denied, .notDetermined] {
            let center = FakeReminderCenter(status: status)
            await ReminderSync.apply([Self.reminder("m1", in: 60)], enabled: true, center: center)
            #expect(await center.pending.isEmpty)
            #expect(await center.authorizationRequests == 0)
        }
    }

    /// iOS peut refuser une notification (journalisé) : les autres sont programmées quand même, la passe suivante réessaie.
    @Test func aRefusedNotificationDoesNotStopTheOthers() async {
        let center = FakeReminderCenter(refusing: ["match-start-m1"])
        await ReminderSync.apply([Self.reminder("m1", in: 60), Self.reminder("m2", in: 90)], enabled: true, center: center)
        #expect(Set(await center.pending.keys) == ["match-start-m2"])
    }

    /// `.task(id:)` annule l'ancienne passe sans l'attendre : annulée, elle ne retire ni ne programme plus rien, pour ne
    /// pas défaire la passe qui la remplace.
    @Test func aCancelledPassTouchesNothing() async {
        let center = FakeReminderCenter()
        await ReminderSync.apply([Self.reminder("old", in: 30)], enabled: true, center: center)
        // La tâche, sur l'acteur principal comme ce test, ne démarre qu'à l'`await` : elle est déjà annulée à son départ.
        let pass = Task { await ReminderSync.apply([Self.reminder("m1", in: 60)], enabled: true, center: center) }
        pass.cancel()
        await pass.value
        #expect(Set(await center.pending.keys) == ["match-start-old"])
    }

    @Test func payloadCarriesTheMatchToOpen() {
        #expect(ReminderPayload.matchId(from: ReminderPayload.userInfo(matchId: "m1")) == "m1")
        #expect(ReminderPayload.matchId(from: ["matchId": 3]) == nil)
        #expect(ReminderPayload.matchId(from: ["matchId": ""]) == nil)
        #expect(ReminderPayload.matchId(from: [:]) == nil)
    }

    @Test func routerHandsTheMatchOverOnce() {
        let router = NotificationRouter()
        #expect(router.consume() == nil)
        router.open(matchId: "m1")
        #expect(router.pendingMatchId == "m1")
        #expect(router.consume() == "m1")
        #expect(router.consume() == nil)
    }
}

/// Le store et iOS : plan tiré du calendrier en cache et des réglages, requête iOS (texte, déclenchement, match à ouvrir),
/// délégué réellement branché sur les deux rappels d'iOS.
@MainActor
@Suite(.serialized)
struct RemindersStoreTests {
    /// Store dont le disque contient : KC suivie (ou personne), réglages donnés, et un calendrier avec KC – G2 dans 3 h
    /// (`m1`), précédé si on le demande d'un KC – G2 terminé hier (`m0`, le dernier match de KC).
    private static func store(settings: AppSettings, followsKC: Bool = true, spoilerFree: Bool = false,
                              finishedMatch: Bool = false) -> (AppStore, Date) {
        let files = TemporaryFiles.store()
        let start = Date().addingTimeInterval(3 * 3600)
        let followed = followsKC
            ? [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp", spoilerFree: spoilerFree)]
            : []
        files.save(FollowList(teams: followed), to: .follows)
        files.save(settings, to: .settings)
        let teams = [
            MatchTeam(id: nil, name: "Karmine Corp", code: "KC", image: nil, result: nil),
            MatchTeam(id: nil, name: "G2 Esports", code: "G2", image: nil, result: nil),
        ]
        var events = [MatchEvent(startTime: start, state: .unstarted, type: "match", blockName: "Play-in",
                                 league: SampleData.worlds,
                                 match: MatchInfo(id: "m1", teams: teams, strategy: Strategy(type: "bestOf", count: 5),
                                                  games: nil),
                                 streams: nil)]
        if finishedMatch {
            let played = [
                MatchTeam(id: nil, name: "Karmine Corp", code: "KC", image: nil,
                          result: MatchTeam.Result(outcome: "win", gameWins: 3)),
                MatchTeam(id: nil, name: "G2 Esports", code: "G2", image: nil,
                          result: MatchTeam.Result(outcome: "loss", gameWins: 1)),
            ]
            events.append(MatchEvent(startTime: Date().addingTimeInterval(-24 * 3600), state: .completed, type: "match",
                                     blockName: "Play-in", league: SampleData.worlds,
                                     match: MatchInfo(id: "m0", teams: played,
                                                      strategy: Strategy(type: "bestOf", count: 5), games: nil),
                                     streams: nil))
        }
        files.save(Cached(value: SchedulePage(leagueIds: [], events: events), fetchedAt: Date()), to: .schedule)
        return (AppStore(transport: ScriptedTransport(mode: .failing), files: files), start)
    }

    @Test func storePlansFromTheCachedScheduleAndSettings() {
        let (store, start) = Self.store(settings: AppSettings(matchRemindersEnabled: true, matchReminderLead: 30 * 60))
        let planned = store.plannedReminders()
        #expect(planned.count == 1)
        #expect(planned.first?.title == "KC vs G2 dans 30 min")
        #expect(planned.first?.subtitle == "Mondial · Play-in · Bo5")
        #expect(planned.first?.fireDate == start.addingTimeInterval(-1800))
        #expect(store.reminderSignature.enabled)

        let (off, _) = Self.store(settings: AppSettings())
        #expect(off.plannedReminders().isEmpty)
        #expect(off.reminderSignature == ReminderSignature(enabled: false, reminders: []))
    }

    /// Règle F1 de l'anti-spoiler : KC suivie en anti-spoiler, dernier match (terminé) masqué → pas de notification de son
    /// prochain match, que la carte cache aussi (« Prochain · masqué ») ; le révéler la rend. Garde, dans l'appli, les
    /// arguments `follows` et `revealed` passés à LoLKit (la règle elle-même est testée dans LoLKit).
    @Test func aNextMatchHiddenByTheAntiSpoilerRuleIsNotPlanned() {
        let (hidden, _) = Self.store(settings: AppSettings(matchRemindersEnabled: true), spoilerFree: true,
                                     finishedMatch: true)
        #expect(hidden.plannedReminders().isEmpty)
        #expect(hidden.reminderSignature == ReminderSignature(enabled: true, reminders: []))

        let (revealed, _) = Self.store(settings: AppSettings(revealedMatchIds: ["m0"], matchRemindersEnabled: true),
                                       spoilerFree: true, finishedMatch: true)
        #expect(revealed.plannedReminders().map(\.matchId) == ["m1"])

        // Même calendrier sans anti-spoiler : le prochain match est annoncé.
        let (open, _) = Self.store(settings: AppSettings(matchRemindersEnabled: true), finishedMatch: true)
        #expect(open.plannedReminders().map(\.matchId) == ["m1"])
    }

    @Test func nothingIsPlannedWhenNoTeamIsFollowed() {
        let (store, _) = Self.store(settings: AppSettings(matchRemindersEnabled: true), followsKC: false)
        #expect(store.plannedReminders().isEmpty)
    }

    @Test func storeSyncSchedulesThroughTheCenter() async {
        let (store, _) = Self.store(settings: AppSettings(matchRemindersEnabled: true))
        let center = FakeReminderCenter()
        await store.syncReminders(center: center)
        #expect(Set(await center.pending.keys) == ["match-start-m1"])
    }

    @Test func iosRequestCarriesTextTimeAndMatch() throws {
        let fire = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 60).rounded(.down) * 60 + 7_200)
        let reminder = MatchReminder(id: "match-start-m1", matchId: "m1", fireDate: fire, title: "KC vs G2 dans 15 min",
                                     subtitle: "Mondial · Play-in · Bo5")
        let request = SystemReminderCenter.request(for: reminder)
        #expect(request.identifier == "match-start-m1")
        #expect(request.content.title == "KC vs G2 dans 15 min")
        #expect(request.content.subtitle == "Mondial · Play-in · Bo5")
        #expect(ReminderPayload.matchId(from: request.content.userInfo) == "m1")
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.repeats == false)
        #expect(trigger.nextTriggerDate() == fire)
    }

    /// Le déclenchement porte le fuseau du calendrier : l'instant visé est celui de `fireDate`, quel que soit le fuseau de
    /// l'iPhone (ici un fuseau à +5 h 30, qui n'est pas celui de la CI).
    @Test func iosTriggerPinsTheTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Kolkata"))
        let fire = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 / 60).rounded(.down) * 60 + 7_200)
        let reminder = MatchReminder(id: "match-start-m1", matchId: "m1", fireDate: fire, title: "KC vs G2 dans 15 min",
                                     subtitle: "Mondial · Play-in · Bo5")
        let request = SystemReminderCenter.request(for: reminder, calendar: calendar)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(trigger.dateComponents.timeZone == calendar.timeZone)
        #expect(trigger.nextTriggerDate() == fire)
    }

    /// Le délégué répond vraiment aux deux rappels d'iOS : une signature qui ne correspondrait pas au protocole serait
    /// ignorée sans erreur (méthode optionnelle d'Objective-C), et toucher une notification n'ouvrirait rien.
    @Test func delegateAnswersBothCallbacks() {
        let delegate = ReminderNotificationDelegate(router: NotificationRouter())
        #expect(delegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))))
        #expect(delegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))))
    }
}

/// La section des Réglages (spec fonctionnalités §2) sans la vue : ce que l'interrupteur et l'avertissement deviennent
/// quand on bascule et quand l'autorisation d'iOS change sans l'appli.
@MainActor
struct MatchRemindersFlowTests {
    private typealias Outcome = MatchRemindersFlow.Outcome

    @Test func leadLabelsNameTheMinutes() {
        #expect(MatchReminders.leadOptions.map { MatchRemindersSection.leadLabel($0) } == ["5 min", "15 min", "30 min"])
        #expect(MatchRemindersSection.leadLabel(MatchReminders.defaultLead) == "15 min")
    }

    @Test func switchingOffNeverAsksIOS() async {
        let center = FakeReminderCenter(status: .notDetermined)
        #expect(await MatchRemindersFlow.toggle(to: false, center: center) == Outcome(enabled: false, denied: false))
        #expect(await center.authorizationRequests == 0)
    }

    @Test func switchingOnWhenAlreadyAuthorizedEnablesWithoutAsking() async {
        let center = FakeReminderCenter(status: .authorized)
        #expect(await MatchRemindersFlow.toggle(to: true, center: center) == Outcome(enabled: true, denied: false))
        #expect(await center.authorizationRequests == 0)
    }

    @Test func switchingOnAsksIOSTheFirstTime() async {
        let center = FakeReminderCenter(status: .notDetermined, grants: true)
        #expect(await MatchRemindersFlow.toggle(to: true, center: center) == Outcome(enabled: true, denied: false))
        #expect(await center.authorizationRequests == 1)
    }

    /// Refus à la demande : l'interrupteur reste coupé et l'avertissement s'affiche ; iOS ne redemande plus, le second
    /// essai ne repose donc pas la question.
    @Test func aRefusalKeepsTheSwitchOffAndSaysWhereToAllow() async {
        let center = FakeReminderCenter(status: .notDetermined, grants: false)
        #expect(await MatchRemindersFlow.toggle(to: true, center: center) == Outcome(enabled: false, denied: true))
        #expect(await center.authorizationRequests == 1)
        #expect(await MatchRemindersFlow.toggle(to: true, center: center) == Outcome(enabled: false, denied: true))
        #expect(await center.authorizationRequests == 1)
    }

    @Test func switchingOnWhenIOSAlreadyDeniedDoesNotAsk() async {
        let center = FakeReminderCenter(status: .denied)
        #expect(await MatchRemindersFlow.toggle(to: true, center: center) == Outcome(enabled: false, denied: true))
        #expect(await center.authorizationRequests == 0)
    }

    /// Au retour au premier plan : autorisée, l'avertissement disparaît ; refusée, il s'affiche si le réglage est activé ou
    /// s'il l'était déjà ; jamais demandée alors que le réglage est activé (sauvegarde restaurée sur un autre iPhone), le
    /// réglage est coupé pour que le prochain basculement demande l'autorisation.
    @Test func reconcilingWithIOSOnReturn() {
        func reconcile(_ enabled: Bool, _ denied: Bool, _ authorization: ReminderAuthorization) -> Outcome {
            MatchRemindersFlow.reconcile(enabled: enabled, denied: denied, authorization: authorization)
        }
        #expect(reconcile(true, true, .authorized) == Outcome(enabled: nil, denied: false))
        #expect(reconcile(false, true, .authorized) == Outcome(enabled: nil, denied: false))
        #expect(reconcile(true, false, .authorized) == Outcome(enabled: nil, denied: false))

        #expect(reconcile(true, false, .denied) == Outcome(enabled: nil, denied: true))
        #expect(reconcile(false, true, .denied) == Outcome(enabled: nil, denied: true))
        #expect(reconcile(false, false, .denied) == Outcome(enabled: nil, denied: false))

        #expect(reconcile(true, false, .notDetermined) == Outcome(enabled: false, denied: false))
        #expect(reconcile(true, true, .notDetermined) == Outcome(enabled: false, denied: false))
        #expect(reconcile(false, false, .notDetermined) == Outcome(enabled: nil, denied: false))
        #expect(reconcile(false, true, .notDetermined) == Outcome(enabled: nil, denied: true))
    }
}
