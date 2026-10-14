import LoLKit
import SwiftUI

/// Page d'un joueur (spec saison §3.4) : en-tête (pseudo, poste, équipe → page d'équipe), périmètres, « sur N games »,
/// moyennes, champions, meilleure game (jamais d'un match masqué), 5 dernières games. Squelettes pendant la lecture du
/// disque. Stats sans les matchs masqués ; s'il n'y a qu'eux : « N matchs masqués » (matchs de l'équipe, ruling I-9).
struct PlayerPageView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.seasonNow) private var fixedNow
    let playerId: String
    @State private var scopeIndex = 0
    @State private var haptics = HapticTrigger()
    @ReduceMotion var reduceMotion

    var body: some View {
        let now = fixedNow ?? Date()
        let games = Array(store.season.games.values)
        let identity = PlayerPageModel.identity(playerId, catalog: store.catalog, games: games)
        let scopes = identity?.teamId.map { store.season.scopes(forTeam: $0, now: now) } ?? []
        let scope = scopes.isEmpty ? nil : scopes[min(scopeIndex, scopes.count - 1)]
        let masked = store.seasonMasked
        let season = store.season.player(playerId, scope: scope, masked: masked)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(identity)
                if scopes.count > 1 {
                    pills(scopes)
                }
                if !store.season.isLoaded {
                    SeasonSkeletonCard(lines: 3, label: String(localized: "Stats en chargement"))
                    SeasonSkeletonCard(lines: 4, label: String(localized: "Champions en chargement"))
                } else if let season, season.games > 0 {
                    Text("sur \(season.games) games").sora(.secondary).foregroundStyle(Palette.secondary)
                    PlayerAveragesCard(season: season)
                    if !season.champions.isEmpty {
                        PlayerChampionsCard(champions: season.champions)
                    }
                    if let best = PlayerPageModel.bestGame(season, masked: masked) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: String(localized: "Meilleure game"))
                            PlayerGameRow(line: best)
                        }
                        .glassCard(radius: Radius.inner, padding: 14)
                    }
                    if !season.recent.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionLabel(text: String(localized: "5 dernières games"))
                            ForEach(season.recent, id: \.gameId) { line in
                                PlayerGameRow(line: line)
                            }
                        }
                        .glassCard(radius: Radius.inner, padding: 14)
                    }
                } else {
                    let hidden = PlayerPageModel.maskedMatchCount(teamId: identity?.teamId,
                                                                  matches: store.season.matches, masked: masked)
                    NoteCard(icon: hidden > 0 ? .eyeOff : .clock,
                             text: hidden > 0 ? String(localized: "Stats masquées · \(hidden) matchs masqués")
                                              : String(localized: "Pas encore de game lue pour ce joueur"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .abyssBackground()
        .navigationTitle(identity?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .haptics(haptics)
    }

    private func header(_ identity: PlayerIdentity?) -> some View {
        HStack(spacing: 12) {
            Text(String((identity?.name ?? "?").prefix(2)).uppercased())
                .sora(.headline)
                .frame(width: 54, height: 54)
                .background(Palette.chipFill, in: Circle())
                .overlay(Circle().strokeBorder(Palette.glassBorder, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(identity?.name ?? SeasonFormat.missing).sora(.title).tracking(Typo.titleTracking)
                Text(SeasonNames.role(identity?.role)).sora(.secondary).foregroundStyle(Palette.secondary)
                if let teamId = identity?.teamId {
                    TeamLink(teamId: teamId) {
                        Text(store.teamName(id: teamId)).sora(.bodyMedium).foregroundStyle(Palette.accent)
                    }
                }
            }
            Spacer()
        }
        .foregroundStyle(Palette.text)
        .glassCard()
    }

    private func pills(_ scopes: [SeasonScope]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(scopes.enumerated()), id: \.offset) { index, scope in
                    PillButton(selected: index == min(scopeIndex, scopes.count - 1), action: {
                        if index != scopeIndex { haptics.play(.gamePicked) }
                        withAnimation(Motion.animation(.snappy, reduceMotion: reduceMotion)) { scopeIndex = index }
                    }) {
                        Text(SeasonLabels.scope(scope))
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}
