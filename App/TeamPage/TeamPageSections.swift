import LoLKit
import SwiftUI

/// En-tête : logo, nom, ligue, étoile (suivre) et œil (anti-spoiler, si suivie) ; verre teinté (Vitrail) si l'équipe est
/// suivie, neutre sinon (spec saison §3.1).
struct TeamPageHeader: View {
    @Environment(AppStore.self) private var store
    let content: TeamPageContent
    let onToggleFollow: () -> Void
    let onToggleSpoiler: () -> Void

    var body: some View {
        let tint = content.followed.map { Palette.team($0.colorHex) }
        HStack(spacing: 12) {
            TeamBadge(code: content.code, logoFile: store.logoFile(for: content.image), tint: tint, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(content.name)
                    .sora(.title)
                    .tracking(Typo.titleTracking)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let league = content.leagueName {
                    Text(league).sora(.secondary).foregroundStyle(Palette.secondary)
                }
            }
            Spacer(minLength: 8)
            if let followed = content.followed {
                Button(action: onToggleSpoiler) {
                    IconView(icon: followed.spoilerFree ? .eyeOff : .eye, size: 20)
                        .foregroundStyle(followed.spoilerFree ? Palette.text : Palette.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(followed.spoilerFree ? Text("Afficher les scores") : Text("Masquer les scores"))
            }
            if content.catalogTeam != nil {
                Button(action: onToggleFollow) {
                    IconView(icon: content.followed == nil ? .star : .starFill, size: 20)
                        .foregroundStyle(content.followed == nil ? Palette.secondary : Palette.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(content.followed == nil ? Text("Suivre") : Text("Ne plus suivre"))
            }
        }
        .buttonStyle(.pressable)
        .foregroundStyle(Palette.text)
        .glassCard(tint: tint)
    }
}

/// « Calculé sur 24 games · 7 à lire · 2 matchs masqués » (chiffres de `TeamSeason`, jamais le nombre de games d'un match
/// masqué).
struct TeamSeasonStatus: View {
    let season: TeamSeason

    var body: some View {
        Text(Self.text(season))
            .sora(.secondary)
            .foregroundStyle(Palette.secondary)
    }

    static func text(_ season: TeamSeason) -> String {
        var parts = [String(localized: "Calculé sur \(season.gamesCounted) games")]
        if season.gamesPending > 0 { parts.append(String(localized: "\(season.gamesPending) à lire")) }
        if season.gamesWithoutStats > 0 { parts.append(String(localized: "\(season.gamesWithoutStats) sans stats")) }
        if season.maskedMatches > 0 { parts.append(String(localized: "\(season.maskedMatches) matchs masqués")) }
        return parts.joined(separator: " · ")
    }
}

/// Bilan (séries et games V-D, série en cours) et forme sur 5 matchs.
struct TeamRecordCard: View {
    let season: TeamSeason

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: String(localized: "Bilan"))
            HStack(spacing: 12) {
                StatTile(value: SeasonFormat.record(season.seriesWins, season.seriesLosses),
                         label: String(localized: "Séries"))
                StatTile(value: SeasonFormat.record(season.gameWins, season.gameLosses),
                         label: String(localized: "Games"))
            }
            if let streak = season.streak, streak.count >= 2 {
                Text(Self.streakText(streak))
                    .sora(.bodyMedium)
                    .foregroundStyle(Palette.text)
            }
            if !season.form.isEmpty {
                HStack(spacing: 10) {
                    Text("Forme").sora(.secondary).foregroundStyle(Palette.secondary)
                    FormPips(form: season.form)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }

    static func streakText(_ streak: Streak) -> String {
        switch streak.kind {
        case .wins: String(localized: "\(streak.count) victoires d'affilée")
        case .losses: String(localized: "\(streak.count) défaites d'affilée")
        }
    }
}

/// Stats moyennes par game (spec saison §3.1) : « — » quand la valeur n'est pas lue (jamais de chiffre inventé).
struct TeamAveragesCard: View {
    let season: TeamSeason

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: String(localized: "Moyennes par game"))
            if let averages = season.averages {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        StatTile(value: SeasonFormat.decimal(averages.kills), label: String(localized: "Kills"))
                        StatTile(value: SeasonFormat.decimal(averages.deaths), label: String(localized: "Morts"))
                        StatTile(value: Format.gold(Int(averages.gold.rounded())), label: String(localized: "Gold"))
                    }
                    GridRow {
                        StatTile(value: SeasonFormat.duration(seconds: averages.durationSeconds),
                                 label: String(localized: "Durée"))
                        StatTile(value: SeasonFormat.decimal(averages.towers), label: String(localized: "Tours"))
                        StatTile(value: SeasonFormat.decimal(averages.inhibitors), label: String(localized: "Inhibiteurs"))
                    }
                    GridRow {
                        StatTile(value: SeasonFormat.decimal(averages.dragons), label: String(localized: "Drakes"))
                        StatTile(value: SeasonFormat.decimal(averages.barons), label: String(localized: "Barons"))
                        StatTile(value: SeasonFormat.signed(averages.gold15Games > 0 ? averages.gold15Diff : nil),
                                 label: String(localized: "Écart de gold à 15 min"),
                                 footnote: String(localized: "sur \(averages.gold15Games) games"))
                    }
                }
                if !season.dragonTypes.isEmpty {
                    DragonTypesRow(types: season.dragonTypes)
                }
            } else {
                Text("Les stats de cette équipe arrivent")
                    .sora(.secondary)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Répartition des types de drakes : icône drake + type + nombre (« Océan × 12 »).
struct DragonTypesRow: View {
    let types: [String: Int]

    var body: some View {
        let sorted = types.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(sorted, id: \.key) { type, count in
                    Chip(muted: true) {
                        IconView(icon: .drake, size: 12)
                        Text("\(Self.name(type)) × \(count)")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(count) drakes \(Self.name(type))"))
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    static func name(_ type: String) -> String {
        switch type {
        case "ocean": String(localized: "Océan")
        case "infernal": String(localized: "Infernal")
        case "mountain": String(localized: "Montagne")
        case "cloud": String(localized: "Nuage")
        case "hextech": String(localized: "Hextech")
        case "chemtech": String(localized: "Chemtech")
        case "elder": String(localized: "Ancien")
        default: type.capitalized
        }
    }
}

/// Champions les plus joués (8 au plus) : icône Data Dragon et nombre de games.
struct TeamChampionsCard: View {
    let champions: [ChampionUse]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: String(localized: "Champions les plus joués"))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
                ForEach(champions.prefix(8), id: \.champion) { use in
                    VStack(spacing: 4) {
                        ChampionIcon(champion: use.champion, size: 40)
                        Text("\(use.games) games").sora(.label).foregroundStyle(Palette.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Prochains matchs (spec saison §3.1) : jamais lus directement (`UpcomingLines`).
struct TeamUpcomingCard: View {
    let lines: UpcomingLines

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: String(localized: "Prochains matchs"))
            switch lines {
            case .hidden:
                HStack(spacing: 6) {
                    IconView(icon: .eyeOff, size: 13)
                    Text("Prochain · masqué")
                }
                .sora(.secondary)
                .foregroundStyle(Palette.secondary)
            case .none:
                Text("Aucun match à venir dans le calendrier")
                    .sora(.secondary)
                    .foregroundStyle(Palette.secondary)
            case let .matches(events):
                ForEach(events) { event in
                    MatchLine(event: event, showsDay: true)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Effectif (catalogue `getTeams`) : poste et pseudo, toucher → page joueur. Monogramme à la place de la photo (aucune
/// image de joueur n'est téléchargée cette nuit).
struct TeamRosterCard: View {
    let players: [TeamPlayer]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: String(localized: "Effectif"))
            ForEach(players) { player in
                NavigationLink(value: PlayerRoute(playerId: player.id)) {
                    HStack(spacing: 10) {
                        Text(String(player.summonerName.prefix(2)).uppercased())
                            .sora(.label)
                            .frame(width: 34, height: 34)
                            .background(Palette.chipFill, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(player.summonerName).sora(.bodyMedium)
                            Text(SeasonNames.role(player.role)).sora(.secondary).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        IconView(icon: .arrow, size: 14).foregroundStyle(Palette.secondary)
                    }
                    .foregroundStyle(Palette.text)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(Text("\(player.summonerName), \(SeasonNames.role(player.role))"))
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Face-à-face de la saison contre le prochain adversaire (matchs masqués exclus et comptés) + lien vers le duel
/// d'équipes.
struct TeamHeadToHeadCard: View {
    let teamId: String
    let opponentId: String
    let headToHead: HeadToHead
    let names: (String, String)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: String(localized: "Face-à-face cette saison"))
            Text("\(names.0) \(headToHead.winsA) – \(headToHead.winsB) \(names.1)")
                .sora(.score)
                .monospacedDigit()
            if headToHead.maskedMatches > 0 {
                Text("\(headToHead.maskedMatches) matchs masqués")
                    .sora(.secondary)
                    .foregroundStyle(Palette.secondary)
            }
            NavigationLink(value: DuelRoute(left: .team(teamId), right: .team(opponentId))) {
                HStack(spacing: 6) {
                    IconView(icon: .versus, size: 14)
                    Text("Comparer les équipes")
                }
                .sora(.bodyMedium)
                .foregroundStyle(Palette.accent)
                .frame(minHeight: 44)
            }
            .buttonStyle(.pressable)
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }
}

/// Ligne « Classement » du tournoi en cours (spec saison §3.5) : rang et bilan → classement complet ; masqué → « toucher
/// pour révéler » (révèle le classement, aucun match).
struct TeamStandingCard: View {
    let line: StandingLine
    let tournamentLabel: String
    let onReveal: (String) -> Void

    var body: some View {
        switch line {
        case let .masked(tournamentId):
            Button { onReveal(tournamentId) } label: {
                HStack(spacing: 6) {
                    IconView(icon: .eyeOff, size: 13)
                    Text("Classement masqué · ")
                    Text("toucher pour révéler").foregroundStyle(Palette.accent)
                }
                .sora(.secondaryMedium)
                .foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .glassCard(radius: Radius.inner, padding: 10)
        case let .ranked(tournamentId, ordinal, wins, losses):
            link(tournamentId, value: "\(Self.ordinal(ordinal)) · \(SeasonFormat.record(wins, losses))")
        case let .record(tournamentId, record):
            link(tournamentId, value: record)
        }
    }

    private func link(_ tournamentId: String, value: String) -> some View {
        NavigationLink(value: StandingsRoute(tournamentId: tournamentId)) {
            HStack {
                IconView(icon: .standings, size: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Classement · \(tournamentLabel)").sora(.secondary).foregroundStyle(Palette.secondary)
                    Text(value).sora(.headline)
                }
                Spacer()
                IconView(icon: .arrow, size: 14).foregroundStyle(Palette.secondary)
            }
            .foregroundStyle(Palette.text)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .glassCard(radius: Radius.inner, padding: 14)
    }

    /// « 1er », « 2e » (« 1st », « 2nd » en anglais).
    static func ordinal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
