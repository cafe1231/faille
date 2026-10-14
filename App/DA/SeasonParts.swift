import LoLKit
import SwiftUI

extension EnvironmentValues {
    /// « Maintenant » des écrans de saison ; nil : l'heure réelle. Les planches PNG le fixent (15/10/2026 15:05 UTC).
    @Entry var seasonNow: Date? = nil
}

/// Icône d'un champion (`championId` du flux, ex. « KSante ») : Data Dragon à la dernière version connue, vignette de repli
/// (initiales) sinon. La version est demandée une fois (`DataDragonStore.version(forPatch: nil)`, liste gardée 24 h) ;
/// toutes les icônes se mettent à jour quand elle arrive. Aperçus : repli, aucune requête.
struct ChampionIcon: View {
    let champion: String
    var size: CGFloat = 28
    @Environment(\.dataDragon) private var dataDragon

    var body: some View {
        let version = dataDragon?.knownVersion(forPatch: nil)
        ZStack {
            DDragonIcon(url: version.map { DataDragon.championImage(version: $0, championId: champion) }, size: size,
                        fallback: DDragonIcon.initials(champion))
        }
        .task {
            if version == nil { _ = await dataDragon?.version(forPatch: nil) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: champion))
    }
}

/// Forme sur 5 matchs (spec saison §3.1) : pastille pleine (victoire), creuse (défaite), œil barré (masqué), dans
/// l'ordre de `TeamSeason.form` (du plus ancien au plus récent : la plus récente à droite). Lue « Forme : Victoire,
/// Défaite, Masqué ».
struct FormPips: View {
    let form: [FormPip]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(form.enumerated()), id: \.offset) { _, pip in
                ZStack {
                    Circle().fill(fill(pip.outcome))
                    Circle().strokeBorder(pip.outcome == .win ? Palette.accent : Palette.glassBorder, lineWidth: 1)
                    if pip.outcome == .masked {
                        IconView(icon: .eyeOff, size: 8).foregroundStyle(Palette.secondary)
                    }
                }
                .frame(width: 14, height: 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Forme : \(Self.spoken(form))"))
    }

    private func fill(_ outcome: FormPip.Outcome) -> Color {
        switch outcome {
        case .win: Palette.accent
        case .loss: Color.white.opacity(0.08)
        case .masked: Color.clear
        }
    }

    static func spoken(_ form: [FormPip]) -> String {
        form.map { pip in
            switch pip.outcome {
            case .win: String(localized: "Victoire")
            case .loss: String(localized: "Défaite")
            case .masked: String(localized: "Masqué")
            }
        }.joined(separator: ", ")
    }
}

/// Une stat moyenne : grand chiffre, libellé dessous, précision optionnelle (« sur 12 games »). Lue d'un bloc.
struct StatTile: View {
    let value: String
    let label: String
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .sora(.stat)
                .monospacedDigit()
                .foregroundStyle(Palette.text)
            Text(label)
                .sora(.secondary)
                .foregroundStyle(Palette.secondary)
            if let footnote {
                Text(footnote)
                    .sora(.label)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Ligne de match des écrans de saison (Accueil, calendrier, page d'équipe, ligues). Anti-spoiler par `Presenter.scoreLine`
/// (`store.scoreLine`) : à venir → l'heure ; en direct → « En direct » (+ score s'il n'est pas masqué ; icône fixe, aucune
/// pulsation dans une liste) ; terminé → le score, ou « Terminé · toucher pour révéler » si masqué. Une ligne masquée
/// terminée avec `onReveal` est tout entière le bouton de révélation ; toute autre ligne est un lien vers le Détail.
/// Un match à venir non révélé d'une équipe dont le dernier match est masqué (règle généralisée de `MustWatch`) n'est
/// qu'une ligne fixe « Match à venir · masqué », non touchable : ni équipes, ni heure, ni lien.
struct MatchLine: View {
    @Environment(AppStore.self) private var store
    let event: MatchEvent
    /// Afficher le jour en plus de l'heure (listes sur plusieurs jours).
    var showsDay = false
    var onReveal: ((String) -> Void)? = nil

    var body: some View {
        if store.isUpcomingMasked(event) {
            hiddenRow
        } else {
            let line = store.scoreLine(event)
            if line.isMasked, event.state == .completed, let onReveal {
                Button { onReveal(event.id) } label: { row(line) }
                    .buttonStyle(.pressable)
                    .accessibilityHint(Text("Révèle le score"))
            } else {
                NavigationLink(value: MatchRoute(matchId: event.id)) { row(line) }
                    .buttonStyle(.pressable)
            }
        }
    }

    /// Règle d'un match à venir caché (testée) : à venir, pas révélé, et une de ses équipes est dans `maskedTeamIds`.
    static func isHiddenUpcoming(_ event: MatchEvent, maskedTeamIds: Set<String>, revealed: Set<String>) -> Bool {
        guard event.state == .unstarted, !revealed.contains(event.id) else { return false }
        return event.match.teams.contains { team in team.id.map(maskedTeamIds.contains) ?? false }
    }

    private var hiddenRow: some View {
        HStack(spacing: 6) {
            IconView(icon: .eyeOff, size: 12)
            Text("Match à venir · masqué")
        }
        .sora(.secondaryMedium)
        .foregroundStyle(Palette.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Match à venir, masqué"))
    }

    private func row(_ line: ScoreLine) -> some View {
        let teams = event.match.teams
        return HStack(spacing: 8) {
            if let left = teams.first { side(left) }
            Spacer(minLength: 6)
            status(line)
            Spacer(minLength: 6)
            if teams.count > 1 { side(teams[1], trailing: true) }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Self.spoken(event, line: line)))
    }

    private func side(_ team: MatchTeam, trailing: Bool = false) -> some View {
        HStack(spacing: 6) {
            if trailing { code(team) }
            TeamBadge(code: team.code, logoFile: store.logoFile(for: team.image), tint: store.tint(for: team), size: 26)
            if !trailing { code(team) }
        }
    }

    private func code(_ team: MatchTeam) -> some View {
        Text(team.code)
            .sora(.headline)
            .foregroundStyle(Palette.text)
            .lineLimit(1)
    }

    @ViewBuilder private func status(_ line: ScoreLine) -> some View {
        switch event.state {
        case .inProgress:
            HStack(spacing: 5) {
                IconView(icon: .live, size: 11)
                if let score = line.score {
                    Text(Format.score(score)).sora(.stat).monospacedDigit()
                } else {
                    Text("En direct").sora(.chip)
                }
            }
            .foregroundStyle(Palette.text)
        case .completed:
            if let score = line.score {
                Text(Format.score(score))
                    .sora(.stat)
                    .monospacedDigit()
                    .foregroundStyle(Palette.text)
            } else {
                HStack(spacing: 4) {
                    IconView(icon: .eyeOff, size: 11)
                    Text("Terminé")
                    if onReveal != nil {
                        Text("· toucher pour révéler").foregroundStyle(Palette.accent)
                    }
                }
                .sora(.secondaryMedium)
                .foregroundStyle(Palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
        case .unstarted, .unknown:
            Text(showsDay ? Format.matchDate(event.startTime)
                          : event.startTime.formatted(date: .omitted, time: .shortened))
                .sora(.secondary)
                .foregroundStyle(Palette.secondary)
        }
    }

    /// « Karmine Corp 2, G2 Esports 1 » ; masqué : « Karmine Corp contre G2 Esports, score masqué » ; à venir :
    /// « Karmine Corp contre G2 Esports, jeu. 16 oct. · 11:00 ».
    static func spoken(_ event: MatchEvent, line: ScoreLine) -> String {
        let names = event.match.teams.map(\.name)
        guard names.count == 2 else { return names.joined(separator: ", ") }
        if let score = line.score, score.count == 2 {
            return String(localized: "\(names[0]) \(score[0]), \(names[1]) \(score[1])")
        }
        switch event.state {
        case .completed, .inProgress:
            return String(localized: "\(names[0]) contre \(names[1]), score masqué")
        case .unstarted, .unknown:
            return String(localized: "\(names[0]) contre \(names[1]), \(Format.matchDate(event.startTime))")
        }
    }
}

/// Lien vers la page d'une équipe (spec saison §2.1 : toucher une équipe partout) ; sans id : le contenu seul.
struct TeamLink<Label: View>: View {
    let teamId: String?
    @ViewBuilder var label: Label

    var body: some View {
        if let teamId {
            NavigationLink(value: TeamRoute(teamId: teamId)) {
                label.contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        } else {
            label
        }
    }
}

/// Deux zones de toucher transparentes à poser en `overlay` sur un `ScoreRow` : le logo et le code de chaque équipe ouvrent
/// sa page ; le score, au centre, reste inerte. Une équipe sans id (calendrier) ou « TBD » n'a pas de zone.
struct TeamTapZones: View {
    let teams: [MatchTeam]

    var body: some View {
        HStack(spacing: 0) {
            zone(teams.first)
            Spacer(minLength: 96)
            zone(teams.count > 1 ? teams[1] : nil)
        }
    }

    @ViewBuilder private func zone(_ team: MatchTeam?) -> some View {
        if let team, let id = team.id, !team.isPlaceholder {
            NavigationLink(value: TeamRoute(teamId: id)) {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(Text("Page de \(team.name)"))
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }
}

/// Squelette d'un bloc de saison : un titre et `lines` lignes, au gabarit d'une carte de verre (spec finitions §10).
struct SeasonSkeletonCard: View {
    var lines = 3
    /// Libellé VoiceOver (« Stats en chargement »), déjà localisé par l'appelant.
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 110, height: 11)
            ForEach(0..<lines, id: \.self) { _ in
                SkeletonBlock(height: 14)
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
    }
}

/// État d'une coquille d'écran pas encore livrée (coupe du lot) : jamais un écran cassé.
struct SeasonComingSoon: View {
    var body: some View {
        ScrollView {
            NoteCard(icon: .clock, text: String(localized: "Bientôt disponible"))
                .padding(.horizontal, 16)
                .padding(.top, 16)
        }
        .abyssBackground()
    }
}
