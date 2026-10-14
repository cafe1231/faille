import LoLKit
import SwiftUI

/// « Joueurs en forme » (spec saison §2.2) : pilules « Semaine / Saison » × « KDA / Kills / CS/min », 5 joueurs (icône
/// du champion le plus joué, pseudo, équipe, valeur) ; toucher → page joueur. Minimum 2 games (semaine) / 5 (saison),
/// matchs masqués exclus (`SeasonStats.topPlayers`). Pendant la collecte : « Les stats arrivent : 12 games lues sur
/// 40 » ; rien de lu : la section n'existe pas.
struct HotPlayersSection: View {
    @Environment(AppStore.self) private var store
    let players: [HotPlayersKey: [PlayerSeason]]
    let progress: CrawlProgress
    @Binding var key: HotPlayersKey
    let onHaptic: (Haptic) -> Void

    var body: some View {
        let list = players[key] ?? []
        if !list.isEmpty || progress.remaining > 0 || progress.read > 0 {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: String(localized: "Joueurs en forme"))
                HStack(spacing: 6) {
                    pill(String(localized: "Semaine"), selected: key.period == .week) {
                        key = HotPlayersKey(period: .week, metric: key.metric)
                    }
                    pill(String(localized: "Saison"), selected: key.period == .season) {
                        key = HotPlayersKey(period: .season, metric: key.metric)
                    }
                    Spacer(minLength: 4)
                    ForEach(PlayerMetric.allCases, id: \.self) { metric in
                        pill(Self.metricName(metric), selected: key.metric == metric) {
                            key = HotPlayersKey(period: key.period, metric: metric)
                        }
                    }
                }
                if list.isEmpty {
                    Text(progress.remaining > 0
                         ? String(localized: "Les stats arrivent : \(progress.read) games lues sur \(progress.read + progress.remaining)")
                         : String(localized: "Pas assez de games pour un classement"))
                        .sora(.secondary)
                        .foregroundStyle(Palette.secondary)
                } else {
                    ForEach(list, id: \.playerId) { player in
                        NavigationLink(value: PlayerRoute(playerId: player.playerId)) { row(player) }
                            .buttonStyle(.pressable)
                            .simultaneousGesture(TapGesture().onEnded { onHaptic(.playerPicked) })
                    }
                }
            }
            .foregroundStyle(Palette.text)
            .glassCard(radius: Radius.inner, padding: 12)
        }
    }

    private func row(_ player: PlayerSeason) -> some View {
        let code = store.teamCode(id: player.teamId) ?? ""
        let name = store.playerName(id: player.playerId, raw: player.name, teamId: player.teamId)
        let value = Self.value(player, metric: key.metric)
        return HStack(spacing: 10) {
            ChampionIcon(champion: player.champions.first?.champion ?? "", size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).sora(.bodyMedium)
                Text(code).sora(.secondary).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Text(value).sora(.stat).monospacedDigit()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(name), \(code), \(Self.metricName(key.metric)) \(value)"))
    }

    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        PillButton(selected: selected, action: {
            if !selected { onHaptic(.gamePicked) }
            action()
        }) {
            Text(title)
        }
    }

    static func metricName(_ metric: PlayerMetric) -> String {
        switch metric {
        case .kda: String(localized: "KDA")
        case .kills: String(localized: "Kills")
        case .csPerMin: String(localized: "CS/min")
        }
    }

    /// KDA, kills moyens par game, CS/min : 1 décimale (`PlayerMetric.value(of:)`).
    static func value(_ player: PlayerSeason, metric: PlayerMetric) -> String {
        SeasonFormat.decimal(metric.value(of: player))
    }
}
