import LoLKit
import SwiftUI

/// Classements et tableaux d'un tournoi (spec saison §3.5) : saison régulière classée, système suisse, phase finale.
/// Masqué (une équipe suivie en anti-spoiler y figure avec un match masqué) : « Classement masqué · toucher pour
/// révéler » ; la révélation est mémorisée pour ce tournoi et ne révèle aucun match. Pas encore lu : une requête (au
/// rythme de la collecte), squelette en attendant ; rien : « Pas encore de classement pour ce tournoi ».
struct StandingsView: View {
    @Environment(AppStore.self) private var store
    let tournamentId: String
    @State private var attempted = false
    @State private var haptics = HapticTrigger()
    @ReduceMotion var reduceMotion

    var body: some View {
        let title = store.season.tournament(id: tournamentId).map(SeasonLabels.tournament) ?? String(localized: "Classement")
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title, subtitle: String(localized: "Classement"))
                if let standings = store.season.standings[tournamentId] {
                    if store.isStandingsMasked(tournamentId: tournamentId) {
                        maskedCard
                    } else {
                        stages(standings)
                            .transition(Motion.revealTransition(reduceMotion: reduceMotion))
                    }
                } else if attempted {
                    NoteCard(icon: .standings,
                             text: store.season.stopReason == .failures
                                 ? String(localized: "Réseau indisponible, réessaie plus tard")
                                 : String(localized: "Pas encore de classement pour ce tournoi"))
                } else {
                    SeasonSkeletonCard(lines: 6, label: String(localized: "Classement en chargement"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .abyssBackground()
        .navigationBarTitleDisplayMode(.inline)
        .haptics(haptics)
        .task {
            await store.season.loadStandings(tournamentId: tournamentId)
            attempted = true
        }
    }

    private var maskedCard: some View {
        Button {
            haptics.play(.reveal)
            withAnimation(Motion.animation(.reveal, reduceMotion: reduceMotion)) {
                store.revealStandings(tournamentId: tournamentId)
            }
        } label: {
            VStack(spacing: 8) {
                IconView(icon: .eyeOff, size: 22)
                Text("Classement masqué").sora(.headline)
                Text("toucher pour révéler").sora(.secondaryMedium).foregroundStyle(Palette.accent)
                Text("Révéler le classement ne révèle aucun match.").sora(.secondary)
                    .foregroundStyle(Palette.secondary)
            }
            .foregroundStyle(Palette.text)
            .frame(maxWidth: .infinity, minHeight: 120)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .glassCard()
    }

    @ViewBuilder private func stages(_ standings: Standings) -> some View {
        ForEach(StandingsTable.build(standings: standings), id: \.id) { stage in
            SectionLabel(text: stage.name)
            switch stage.content {
            case let .table(rows):
                if rows.isEmpty {
                    NoteCard(icon: .standings, text: String(localized: "Pas encore de classement pour cette étape"))
                } else {
                    StandingsTableCard(rows: rows)
                }
            case let .swiss(groups):
                SwissGroupsCard(groups: groups)
            case let .bracket(rounds):
                BracketCard(rounds: rounds.map { (StandingsTexts.roundName($0.kind), $0.matches) })
            case let .matches(matches):
                BracketCard(rounds: [(nil, matches)])
            }
        }
    }
}
