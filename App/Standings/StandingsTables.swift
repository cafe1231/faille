import LoLKit
import SwiftUI

/// Classement d'une saison régulière : rang, équipe (lien vers sa page), bilan ; ligne teintée pour une équipe suivie.
struct StandingsTableCard: View {
    @Environment(AppStore.self) private var store
    let rows: [StandingsTable.Row]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(rows, id: \.team.id) { row in
                let followed = store.follows.team(id: row.team.id)
                TeamLink(teamId: row.team.id) {
                    HStack(spacing: 10) {
                        Text("\(row.ordinal)").sora(.stat).monospacedDigit().frame(width: 26, alignment: .trailing)
                        TeamBadge(code: row.team.code, logoFile: store.logoFile(for: row.team.image),
                                  tint: followed.map { Palette.team($0.colorHex) }, size: 28)
                        Text(row.team.name).sora(.bodyMedium).lineLimit(1)
                        Spacer()
                        Text(SeasonFormat.record(row.wins, row.losses)).sora(.stat).monospacedDigit()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(followed.map { Palette.team($0.colorHex).opacity(0.14) } ?? .clear,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .foregroundStyle(Palette.text)
                .accessibilityElement(children: .combine)
            }
        }
        .glassCard(radius: Radius.inner, padding: 10)
    }
}

/// Système suisse : groupes par bilan (« 2-1 »), recalculés depuis les matchs terminés (`StandingsTable`).
struct SwissGroupsCard: View {
    @Environment(AppStore.self) private var store
    let groups: [StandingsTable.RecordGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups, id: \.record) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.record).sora(.headline).monospacedDigit()
                    FlowRow(teams: group.teams)
                }
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Équipes d'un groupe, en pastilles qui passent à la ligne.
private struct FlowRow: View {
    @Environment(AppStore.self) private var store
    let teams: [MatchTeam]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(Array(teams.enumerated()), id: \.offset) { _, team in
                TeamLink(teamId: team.id) {
                    Chip(muted: store.tint(for: team) == nil) {
                        Text(StandingsTexts.teamLabel(team))
                    }
                }
            }
        }
    }
}

/// Tableau à élimination ou liste de matchs : tours nommés (quarts, demies, finale) ou matchs dans l'ordre de l'API,
/// chaque match avec ses deux équipes et son score (le tableau entier est déjà masqué ou révélé par `StandingsView`).
struct BracketCard: View {
    @Environment(AppStore.self) private var store
    /// (nom du tour, ou nil pour une simple liste ; matchs).
    let rounds: [(name: String?, matches: [BracketMatch])]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(rounds.enumerated()), id: \.offset) { _, round in
                VStack(alignment: .leading, spacing: 6) {
                    if let name = round.name {
                        Text(name).sora(.label).tracking(Typo.labelTracking).textCase(.uppercase)
                            .foregroundStyle(Palette.secondary)
                    }
                    ForEach(round.matches, id: \.id) { match in
                        BracketMatchRow(match: match,
                                        showsScore: BracketMatchRow.showsScore(match, follows: store.follows,
                                                                               revealed: store.settings.revealedMatchIds))
                    }
                }
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

struct BracketMatchRow: View {
    let match: BracketMatch
    let showsScore: Bool

    /// Tableau révélé ≠ match révélé : le score (longueur de la série) d'un match encore masqué ailleurs reste caché,
    /// la ligne dit « vs ».
    static func showsScore(_ match: BracketMatch, follows: FollowList, revealed: Set<String>) -> Bool {
        match.state == .completed && match.teams.count == 2
            && !SpoilerPolicy.isMasked(match.teams, matchId: match.id, follows: follows, revealed: revealed)
    }

    var body: some View {
        let teams = match.teams
        HStack {
            Text(teams.first.map(StandingsTexts.teamLabel) ?? "—").sora(.bodyMedium)
            Spacer()
            if showsScore {
                Text(Format.score(teams.map(\.gameWins))).sora(.stat).monospacedDigit()
            } else {
                Text("vs").sora(.secondary).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Text(teams.count > 1 ? StandingsTexts.teamLabel(teams[1]) : "—").sora(.bodyMedium)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
