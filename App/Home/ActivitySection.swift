import LoLKit
import SwiftUI

/// « Activité récente » (spec saison §2.4) : ce que les données disent vraiment (`HomeFeed.activity`, jamais pour un
/// match masqué). Squelette de 2 lignes pendant la lecture du disque ; vide : la section n'existe pas.
struct ActivitySection: View {
    @Environment(AppStore.self) private var store
    let items: [ActivityItem]
    let loading: Bool

    var body: some View {
        if loading {
            SeasonSkeletonCard(lines: 2, label: String(localized: "Activité en chargement"))
        } else if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: String(localized: "Activité récente"))
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    row(item.kind)
                }
            }
            .foregroundStyle(Palette.text)
            .glassCard(radius: Radius.inner, padding: 12)
        }
    }

    @ViewBuilder private func row(_ kind: ActivityKind) -> some View {
        let text = ActivityText.text(kind, store: store)
        if let route = ActivityText.matchRoute(kind, store: store) {
            NavigationLink(value: route) { line(kind, text) }.buttonStyle(.pressable)
        } else if case let .streak(teamId, _, _) = kind {
            NavigationLink(value: TeamRoute(teamId: teamId)) { line(kind, text) }.buttonStyle(.pressable)
        } else {
            line(kind, text)
        }
    }

    private func line(_ kind: ActivityKind, _ text: String) -> some View {
        HStack(spacing: 8) {
            IconView(icon: ActivityText.icon(kind), size: 14).foregroundStyle(Palette.accent)
            Text(text).sora(.body).multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Phrases de l'activité (spec saison §2.4 : LoLKit donne des valeurs, l'appli formule).
@MainActor
enum ActivityText {
    static func text(_ kind: ActivityKind, store: AppStore) -> String {
        switch kind {
        case let .justFinished(matchId):
            guard let event = store.event(id: matchId) else { return String(localized: "Un match vient de se terminer") }
            let line = store.scoreLine(event)
            let codes = line.teamCodes
            if let score = line.score, codes.count == 2, score.count == 2 {
                return String(localized: "Terminé : \(codes[0]) \(score[0]) – \(score[1]) \(codes[1])")
            }
            return String(localized: "Terminé : \(codes.joined(separator: " – "))")
        case let .streak(teamId, streakKind, count):
            let code = store.teamCode(id: teamId) ?? teamId
            return streakKind == .wins ? String(localized: "\(code) : \(count) victoires d'affilée")
                                       : String(localized: "\(code) : \(count) défaites d'affilée")
        case let .killRecord(_, teamId, kills):
            return String(localized: "Record de kills : \(store.teamCode(id: teamId) ?? teamId), \(kills) kills en une game")
        case let .bigGame(gameId, playerId, kills):
            return String(localized: "\(playerName(playerId, gameId: gameId, store: store)) : \(kills) kills en une game")
        case let .fastGame(_, seconds):
            return String(localized: "Game éclair : \(SeasonFormat.duration(seconds: Double(seconds)))")
        case let .longGame(_, seconds):
            return String(localized: "Game marathon : \(SeasonFormat.duration(seconds: Double(seconds)))")
        case let .comeback15(_, teamId, deficit):
            return String(localized: "Retournement : \(store.teamCode(id: teamId) ?? teamId) gagne après \(SeasonFormat.signed(Double(-deficit))) gold à 15 min")
        }
    }

    static func icon(_ kind: ActivityKind) -> Icon {
        switch kind {
        case .justFinished: .check
        case .streak: .trophy
        case .killRecord, .bigGame: .swords
        case .fastGame, .longGame: .clock
        case .comeback15: .gold
        }
    }

    /// Détail du match d'une game (jamais masqué : `HomeFeed.activity` l'exclut).
    static func matchRoute(_ kind: ActivityKind, store: AppStore) -> MatchRoute? {
        switch kind {
        case let .justFinished(matchId): return MatchRoute(matchId: matchId)
        case let .killRecord(gameId, _, _), let .bigGame(gameId, _, _), let .fastGame(gameId, _),
             let .longGame(gameId, _), let .comeback15(gameId, _, _):
            return store.season.games[gameId].map { MatchRoute(matchId: $0.matchId) }
        case .streak: return nil
        }
    }

    private static func playerName(_ playerId: String, gameId: String, store: AppStore) -> String {
        guard let found = store.season.games[gameId]?.player(playerId) else { return playerId }
        return store.playerName(id: playerId, raw: found.line.name, teamId: found.team.teamId)
    }
}
