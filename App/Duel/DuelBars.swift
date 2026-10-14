import LoLKit
import SwiftUI

/// Une barre en miroir (spec saison §3.3) : valeur de gauche, deux demi-barres partant du centre (largeur = valeur / max
/// des deux, `Motion.smooth`), valeur de droite ; « — » sans valeur. Lue « KDA : Canna 3,4, BrokenBlade 4,1 ».
struct DuelBarRow: View {
    let bar: DuelBar
    let names: (String, String)
    var tints: (Color, Color) = (Palette.accent, Palette.text.opacity(0.7))
    @ReduceMotion var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            Text(DuelTexts.metric(bar.metric)).sora(.label).foregroundStyle(Palette.secondary)
            HStack(spacing: 8) {
                Text(DuelTexts.value(bar.left, metric: bar.metric))
                    .sora(.stat).monospacedDigit().frame(width: 52, alignment: .trailing)
                GeometryReader { proxy in
                    let half = proxy.size.width / 2
                    HStack(spacing: 2) {
                        Spacer(minLength: 0)
                        Capsule().fill(tints.0).frame(width: max(0, (half - 1) * bar.leftRatio))
                        Capsule().fill(tints.1).frame(width: max(0, (half - 1) * bar.rightRatio))
                        Spacer(minLength: 0)
                    }
                    .frame(width: proxy.size.width)
                }
                .frame(height: 6)
                .animation(Motion.animation(.smooth, reduceMotion: reduceMotion), value: bar)
                Text(DuelTexts.value(bar.right, metric: bar.metric))
                    .sora(.stat).monospacedDigit().frame(width: 52, alignment: .leading)
            }
        }
        .foregroundStyle(Palette.text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(DuelTexts.metric(bar.metric)) : \(names.0) \(DuelTexts.value(bar.left, metric: bar.metric)), \(names.1) \(DuelTexts.value(bar.right, metric: bar.metric))"))
    }
}

/// Textes du duel.
enum DuelTexts {
    static func metric(_ metric: DuelMetric) -> String {
        switch metric {
        case .kda: String(localized: "KDA")
        case .csPerMin: String(localized: "CS/min")
        case .goldPerMin: String(localized: "Gold/min")
        case .damageShare: String(localized: "Part des dégâts")
        case .killParticipation: String(localized: "Participation aux kills")
        }
    }

    static func value(_ value: Double?, metric: DuelMetric) -> String {
        guard let value else { return SeasonFormat.missing }
        switch metric {
        case .kda, .csPerMin: return SeasonFormat.decimal(value)
        case .goldPerMin: return SeasonFormat.integer(value)
        case .damageShare, .killParticipation: return SeasonFormat.percent(value)
        }
    }
}

/// Un face-à-face de joueurs : noms, barres, 3 champions favoris de chaque côté, et la ligne « Cette game » si elle est
/// connue (game jouée d'un match non masqué).
struct PlayerDuelCard: View {
    let role: String?
    let left: DuelPlayer?
    let right: DuelPlayer?
    /// Stats de saison déjà calculées par l'écran (`Duel.players`, matchs masqués exclus ; I-8) : la carte ne relit
    /// ni le store ni les games.
    let duel: PlayerDuel
    var onChange: ((DuelSidePosition) -> Void)? = nil

    var body: some View {
        let leftSeason = duel.left
        let rightSeason = duel.right
        let names = (left?.name ?? SeasonFormat.missing, right?.name ?? SeasonFormat.missing)
        VStack(spacing: 10) {
            HStack {
                playerName(left, season: leftSeason, position: .left)
                Spacer()
                if let role { Text(SeasonNames.role(role)).sora(.label).foregroundStyle(Palette.secondary) }
                Spacer()
                playerName(right, season: rightSeason, position: .right)
            }
            ForEach(duel.bars, id: \.metric) { bar in
                DuelBarRow(bar: bar, names: names)
            }
            HStack {
                champions(leftSeason)
                Spacer()
                champions(rightSeason)
            }
            if left?.thisGame != nil || right?.thisGame != nil {
                HStack {
                    thisGame(left?.thisGame)
                    Spacer()
                    Text("Cette game").sora(.label).foregroundStyle(Palette.secondary)
                    Spacer()
                    thisGame(right?.thisGame)
                }
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func playerName(_ player: DuelPlayer?, season: PlayerSeason?, position: DuelSidePosition) -> some View {
        VStack(alignment: position == .left ? .leading : .trailing, spacing: 2) {
            if let player {
                NavigationLink(value: PlayerRoute(playerId: player.id)) {
                    Text(player.name).sora(.headline).lineLimit(1)
                }
                .buttonStyle(.pressable)
            } else {
                Text(SeasonFormat.missing).sora(.headline)
            }
            Text(season.map { String(localized: "sur \($0.games) games") } ?? String(localized: "aucune game lue"))
                .sora(.label).foregroundStyle(Palette.secondary)
            if let onChange {
                Button { onChange(position) } label: {
                    Text("Changer").sora(.label).foregroundStyle(Palette.accent).frame(minHeight: 32)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("Changer de joueur"))
            }
        }
    }

    private func champions(_ season: PlayerSeason?) -> some View {
        HStack(spacing: 4) {
            ForEach(season?.champions.prefix(3).map(\.champion) ?? [], id: \.self) { champion in
                ChampionIcon(champion: champion, size: 26)
            }
        }
    }

    private func thisGame(_ line: PlayerGameLine?) -> some View {
        HStack(spacing: 6) {
            if let line {
                ChampionIcon(champion: line.champion, size: 22)
                Text(SeasonFormat.kda(kills: line.kills, deaths: line.deaths, assists: line.assists))
                    .sora(.secondaryMedium).monospacedDigit()
                Text("\(line.creepScore) CS").sora(.secondary).foregroundStyle(Palette.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Côté d'un face-à-face (bouton « Changer »).
enum DuelSidePosition: Hashable {
    case left, right
}

/// Duel d'équipes (spec saison §3.3) : bilans et moyennes de la saison côte à côte, et face-à-face de la saison
/// (matchs masqués exclus et comptés).
struct TeamDuelCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.seasonNow) private var fixedNow
    let leftId: String
    let rightId: String
    /// Matchs masqués, calculés une fois par l'écran (I-8).
    let masked: Set<String>

    var body: some View {
        let now = fixedNow ?? Date()
        let left = season(leftId, now: now, masked: masked)
        let right = season(rightId, now: now, masked: masked)
        let h2h = SeasonStats.headToHead(leftId, rightId, matches: store.season.matches, masked: masked)
        let codes = (store.teamCode(id: leftId) ?? leftId, store.teamCode(id: rightId) ?? rightId)
        VStack(alignment: .leading, spacing: 12) {
            Text("Cette saison : \(codes.0) \(h2h.winsA) – \(h2h.winsB) \(codes.1)").sora(.headline)
            if h2h.maskedMatches > 0 {
                Text("\(h2h.maskedMatches) matchs masqués").sora(.secondary).foregroundStyle(Palette.secondary)
            }
            ForEach(store.season.matches.filter { h2h.matchIds.contains($0.id) }) { match in
                if let event = store.event(id: match.id) {
                    MatchLine(event: event, showsDay: true)
                }
            }
            row(String(localized: "Séries"), left.map { SeasonFormat.record($0.seriesWins, $0.seriesLosses) },
                right.map { SeasonFormat.record($0.seriesWins, $0.seriesLosses) })
            row(String(localized: "Games"), left.map { SeasonFormat.record($0.gameWins, $0.gameLosses) },
                right.map { SeasonFormat.record($0.gameWins, $0.gameLosses) })
            row(String(localized: "Kills par game"), left?.averages.map { SeasonFormat.decimal($0.kills) },
                right?.averages.map { SeasonFormat.decimal($0.kills) })
            row(String(localized: "Morts par game"), left?.averages.map { SeasonFormat.decimal($0.deaths) },
                right?.averages.map { SeasonFormat.decimal($0.deaths) })
            row(String(localized: "Durée moyenne"), left?.averages.map { SeasonFormat.duration(seconds: $0.durationSeconds) },
                right?.averages.map { SeasonFormat.duration(seconds: $0.durationSeconds) })
            row(String(localized: "Drakes par game"), left?.averages.map { SeasonFormat.decimal($0.dragons) },
                right?.averages.map { SeasonFormat.decimal($0.dragons) })
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func season(_ teamId: String, now: Date, masked: Set<String>) -> TeamSeason? {
        guard let scope = store.season.scopes(forTeam: teamId, now: now).first, !scope.tournamentIds.isEmpty else { return nil }
        return store.season.teamSeason(teamId, scope: scope, masked: masked, now: now)
    }

    private func row(_ label: String, _ left: String?, _ right: String?) -> some View {
        HStack {
            Text(left ?? SeasonFormat.missing).sora(.stat).monospacedDigit()
            Spacer()
            Text(label).sora(.secondary).foregroundStyle(Palette.secondary)
            Spacer()
            Text(right ?? SeasonFormat.missing).sora(.stat).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
