import LoLKit
import SwiftUI

/// Section « Ligues » de l'onglet Matchs (spec saison §3.5), après les cartes : une ligne par ligue suivie — prochain
/// match (anti-spoiler : « Prochain · masqué » selon la règle C), lien « Classement » du tournoi en cours. Aucune ligue
/// suivie : la section n'existe pas.
struct LeaguesSection: View {
    let rows: [LeagueRowContent]

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: String(localized: "Ligues"))
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(row.league.name).sora(.headline)
                            Spacer()
                            if let tournamentId = row.tournamentId {
                                NavigationLink(value: StandingsRoute(tournamentId: tournamentId)) {
                                    HStack(spacing: 4) {
                                        IconView(icon: .standings, size: 13)
                                        Text("Classement")
                                    }
                                    .sora(.secondaryMedium)
                                    .foregroundStyle(Palette.accent)
                                    .frame(minHeight: 44)
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                        switch row.next {
                        case let .match(event):
                            MatchLine(event: event, showsDay: true)
                        case .hidden:
                            HStack(spacing: 6) {
                                IconView(icon: .eyeOff, size: 13)
                                Text("Prochain · masqué")
                            }
                            .sora(.secondary)
                            .foregroundStyle(Palette.secondary)
                        case .none:
                            Text("Aucun match à venir dans le calendrier").sora(.secondary)
                                .foregroundStyle(Palette.secondary)
                        }
                    }
                    .foregroundStyle(Palette.text)
                    .glassCard(radius: Radius.inner, padding: 12)
                }
            }
        }
    }

    /// Lignes depuis le store (I2 les passe à la section).
    @MainActor
    static func rows(store: AppStore, now: Date = Date()) -> [LeagueRowContent] {
        let current = Dictionary(uniqueKeysWithValues: store.follows.leagues.compactMap { league in
            store.currentTournamentId(leagueId: league.id, now: now).map { (league.id, $0) }
        })
        return LeagueRows.rows(follows: store.follows, schedule: store.schedule, revealed: store.settings.revealedMatchIds,
                               maskedLatestTeamIds: store.maskedLatestTeamIds, currentTournamentIds: current, now: now)
    }
}
