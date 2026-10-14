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
    private(set) var authorizationRequests = 0

    init(status: ReminderAuthorization = .authorized, grants: Bool = true, foreign: Set<String> = []) {
        self.status = status
        self.grants = grants
        self.foreign = foreign
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
    /// Store dont le disque contient : KC suivie, réglages donnés, et un calendrier avec KC – G2 dans 3 h.
    private static func store(settings: AppSettings) -> (AppStore, Date) {
        let files = TemporaryFiles.store()
        let start = Date().addingTimeInterval(3 * 3600)
        files.save(FollowList(teams: [FollowedTeam(id: "kc", code: "KC", name: "Karmine Corp")]), to: .follows)
        files.save(settings, to: .settings)
        let teams = [
            MatchTeam(id: nil, name: "Karmine Corp", code: "KC", image: nil, result: nil),
            MatchTeam(id: nil, name: "G2 Esports", code: "G2", image: nil, result: nil),
        ]
        let event = MatchEvent(startTime: start, state: .unstarted, type: "match", blockName: "Play-in",
                               league: SampleData.worlds,
                               match: MatchInfo(id: "m1", teams: teams, strategy: Strategy(type: "bestOf", count: 5),
                                                games: nil),
                               streams: nil)
        files.save(Cached(value: SchedulePage(leagueIds: [], events: [event]), fetchedAt: Date()), to: .schedule)
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

    /// Le délégué répond vraiment aux deux rappels d'iOS : une signature qui ne correspondrait pas au protocole serait
    /// ignorée sans erreur (méthode optionnelle d'Objective-C), et toucher une notification n'ouvrirait rien.
    @Test func delegateAnswersBothCallbacks() {
        let delegate = ReminderNotificationDelegate(router: NotificationRouter())
        #expect(delegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))))
        #expect(delegate.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))))
    }
}
