import LoLKit
import SwiftUI

/// Moyennes d'un joueur (spec saison §3.4) : K/D/A par game, KDA, CS/min, gold/min, participation aux kills, part des
/// dégâts « sur N games enrichies » ou « — ».
struct PlayerAveragesCard: View {
    let season: PlayerSeason

    var body: some View {
        let games = Double(max(1, season.games))
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: String(localized: "Moyennes"))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow {
                    StatTile(value: "\(SeasonFormat.decimal(Double(season.kills) / games))/\(SeasonFormat.decimal(Double(season.deaths) / games))/\(SeasonFormat.decimal(Double(season.assists) / games))",
                             label: String(localized: "K/D/A par game"))
                    StatTile(value: SeasonFormat.decimal(season.kda), label: String(localized: "KDA"))
                }
                GridRow {
                    StatTile(value: SeasonFormat.decimal(season.csPerMin), label: String(localized: "CS/min"))
                    StatTile(value: SeasonFormat.integer(season.goldPerMin), label: String(localized: "Gold/min"))
                }
                GridRow {
                    StatTile(value: SeasonFormat.percent(season.killParticipation),
                             label: String(localized: "Participation aux kills"))
                    StatTile(value: SeasonFormat.percent(season.damageShareGames > 0 ? season.damageShare : nil),
                             label: String(localized: "Part des dégâts"),
                             footnote: String(localized: "sur \(season.damageShareGames) games enrichies"))
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Champions joués : icône, games, bilan V-D (« estimé » si un vainqueur est déduit).
struct PlayerChampionsCard: View {
    let champions: [ChampionUse]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: String(localized: "Champions joués"))
            ForEach(champions, id: \.champion) { use in
                HStack(spacing: 10) {
                    ChampionIcon(champion: use.champion, size: 32)
                    Text(use.champion).sora(.bodyMedium)
                    Spacer()
                    Text("\(use.games) games").sora(.secondary).foregroundStyle(Palette.secondary)
                    Text(SeasonFormat.record(use.wins, use.games - use.wins)).sora(.stat).monospacedDigit()
                    if use.winsEstimated {
                        Text("estimé").sora(.label).foregroundStyle(Palette.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Une game de la liste (meilleure game, 5 dernières) : champion, K/D/A, CS, résultat si connu (« estimé » si déduit) ;
/// toucher → Détail du match. Les games d'un match masqué n'arrivent jamais ici (`SeasonStats.player`).
struct PlayerGameRow: View {
    let line: GameRefLine

    var body: some View {
        NavigationLink(value: MatchRoute(matchId: line.matchId)) {
            HStack(spacing: 10) {
                ChampionIcon(champion: line.champion, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(SeasonFormat.kda(kills: line.kills, deaths: line.deaths, assists: line.assists))
                        .sora(.stat).monospacedDigit()
                    Text(line.startedAt.formatted(date: .abbreviated, time: .omitted))
                        .sora(.secondary).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Text("\(line.creepScore) CS").sora(.secondary).foregroundStyle(Palette.secondary)
                result
            }
            .foregroundStyle(Palette.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder private var result: some View {
        if let won = line.won {
            HStack(spacing: 3) {
                Text(won ? String(localized: "V") : String(localized: "D")).sora(.stat)
                if line.winEstimated {
                    Text("estimé").sora(.label).foregroundStyle(Palette.secondary)
                }
            }
            .accessibilityLabel(won ? Text("Victoire") : Text("Défaite"))
        }
    }
}
