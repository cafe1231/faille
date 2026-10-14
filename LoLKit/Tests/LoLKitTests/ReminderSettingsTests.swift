import Foundation
import Testing
// Volontairement SANS `@testable` : l'appli lit et écrit ces réglages avec la seule API publique.
import LoLKit

/// Réglages des notifications de début de match (spec fonctionnalités §2) : désactivées par défaut, délai de 15 min,
/// décodage tolérant (un `settings.json` d'avant ce lot, ou un délai inconnu, garde les valeurs par défaut).
struct ReminderSettingsTests {
    @Test func remindersAreOffByDefaultWithAFifteenMinuteLead() {
        let settings = AppSettings()
        #expect(settings.matchRemindersEnabled == false)
        #expect(settings.matchReminderLead == 15 * 60)
        #expect(settings.matchReminderLead == MatchReminders.defaultLead)
    }

    @Test func reminderSettingsRoundTrip() throws {
        let custom = AppSettings(liveActivityMode: .manual, revealedMatchIds: ["m1"], matchRemindersEnabled: true,
                                 matchReminderLead: 5 * 60)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(custom))
        #expect(decoded == custom)
        #expect(decoded.matchRemindersEnabled)
        #expect(decoded.matchReminderLead == 300)
    }

    @Test func settingsFromBeforeThisLotKeepTheDefaults() throws {
        let old = #"{"liveActivityMode":"manual","revealedMatchIds":["m1"]}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(decoded.liveActivityMode == .manual)
        #expect(decoded.revealedMatchIds == ["m1"])
        #expect(decoded.matchRemindersEnabled == false)
        #expect(decoded.matchReminderLead == MatchReminders.defaultLead)
    }

    @Test func unknownLeadOrUnreadableSwitchFallsBackToTheDefaults() throws {
        let odd = #"{"matchRemindersEnabled":"oui","matchReminderLead":600}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(odd.utf8))
        #expect(decoded.matchRemindersEnabled == false)
        #expect(decoded.matchReminderLead == MatchReminders.defaultLead)
        #expect(AppSettings(matchReminderLead: 42).matchReminderLead == MatchReminders.defaultLead)
        var settings = AppSettings(matchReminderLead: 30 * 60)
        #expect(settings.matchReminderLead == 1800)
        settings.matchReminderLead = 7
        #expect(settings.matchReminderLead == MatchReminders.defaultLead)
    }
}
