import Foundation
import LoLKit
import SwiftUI
import Testing
@testable import Faille

extension ApercuTests {
    /// Réglage « Notifications de début de match » (spec fonctionnalités §2) : coupé (défaut), activé à 15 min, refusé
    /// par iOS.
    @Test func remindersBoard() async throws {
        let board = ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader("Notifications", subtitle: "Coupées · 15 min · refusées par iOS")
                SectionLabel(text: "Notifications")
                MatchRemindersSection(enabled: false, lead: MatchReminders.defaultLead, center: InertReminderCenter(),
                                      setEnabled: { _ in }, setLead: { _ in })
                MatchRemindersSection(enabled: true, lead: MatchReminders.defaultLead, center: InertReminderCenter(),
                                      setEnabled: { _ in }, setLead: { _ in })
                MatchRemindersSection(enabled: false, lead: MatchReminders.defaultLead, center: InertReminderCenter(),
                                      denied: true, setEnabled: { _ in }, setLead: { _ in })
            }
            .padding(.horizontal, 16)
        }
        .abyssBackground()
        let url = try await Snapshot.write(board, named: "17-notifications")
        expectNotBlank(url)
    }
}
