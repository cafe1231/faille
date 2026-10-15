import LoLKit
import SwiftUI

/// Page 1 : « Ton compagnon de saison LoL esport », l'exemple vivant.
struct OnboardingWelcomePage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Ton compagnon de saison LoL esport")
                .sora(.title).tracking(Typo.titleTracking)
            Text("Les matchs en direct, les résultats, les stats de saison de tes équipes et de leurs joueurs, au même endroit.")
                .sora(.body).foregroundStyle(Palette.secondary)
            OnboardingExampleCard()
        }
        .foregroundStyle(Palette.text)
    }
}

/// Page 2 : « Choisis tes équipes ou une ligue » — pilules de ligues, recherche, équipes du Mondial en grille de logos ;
/// toucher = suivre tout de suite.
struct OnboardingPickPage: View {
    let teams: [Team]
    let leagues: [League]
    let followedTeamIds: Set<String>
    let followedLeagueIds: Set<String>
    let search: (String) -> [Team]
    let onToggleTeam: (Team) -> Void
    let onToggleLeague: (League) -> Void
    @State private var query = ""
    /// Équipes montrées dans la grille ; au-delà, une mention invite à chercher.
    static let gridLimit = 40

    var body: some View {
        let shown = query.trimmingCharacters(in: .whitespaces).isEmpty ? teams : search(query)
        VStack(alignment: .leading, spacing: 14) {
            Text("Choisis tes équipes ou une ligue").sora(.title).tracking(Typo.titleTracking)
            // Pilules de ligues : débordent jusqu'au bord de l'écran (audit B-G2) au lieu d'être rognées à la gouttière.
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(leagues) { league in
                        leaguePill(league, followed: followedLeagueIds.contains(league.id))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
            HStack(spacing: 8) {
                IconView(icon: .search, size: 16).foregroundStyle(Palette.secondary)
                TextField("", text: $query, prompt: Text("Rechercher une équipe").foregroundStyle(Palette.secondary))
                    .sora(.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Palette.fill(.subtle), in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            if query.isEmpty {
                Text("Équipes du Mondial").sora(.label).tracking(Typo.labelTracking).textCase(.uppercase)
                    .foregroundStyle(Palette.secondary)
            }
            if teams.isEmpty && query.isEmpty {
                loadingGrid
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(shown.prefix(Self.gridLimit)) { team in
                        teamCell(team, followed: followedTeamIds.contains(team.id))
                    }
                }
            }
            if shown.count > Self.gridLimit {
                Text("\(Self.gridLimit) équipes affichées sur \(shown.count) : affine avec la recherche.")
                    .sora(.secondary).foregroundStyle(Palette.secondary)
            }
        }
        .foregroundStyle(Palette.text)
    }

    /// Catalogue pas encore lu (premier lancement, réseau lent ou absent) : squelette de la grille et une note, au lieu
    /// d'un titre sans rien dessous (audit D.1, saison 7).
    private var loadingGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShimmerScope {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonBlock(height: 104, radius: Radius.inner)
                    }
                }
            }
            Text("Les équipes arrivent dès que la connexion revient.")
                .sora(.secondary).foregroundStyle(Palette.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// Pilule de ligue : « suivie » = verre, bordure et étoile à l'accent ; jamais le blanc, qui veut dire « filtre choisi »
    /// partout ailleurs (audit B-O2).
    private func leaguePill(_ league: League, followed: Bool) -> some View {
        Button { onToggleLeague(league) } label: {
            HStack(spacing: 4) {
                if followed { IconView(icon: .starFill, size: 11) }
                Text(league.name)
            }
            .sora(followed ? .secondaryMedium : .secondary)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(followed ? Palette.accent : Palette.secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(Capsule().fill(Palette.fill(.subtle)))
            .overlay(Capsule().strokeBorder(followed ? Palette.accent : Palette.glassBorder, lineWidth: 1))
            .frame(minHeight: PillButton<EmptyView>.touchHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityValue(followed ? Text("Suivie") : Text("Pas suivie"))
    }

    private func teamCell(_ team: Team, followed: Bool) -> some View {
        Button { onToggleTeam(team) } label: {
            VStack(spacing: 6) {
                TeamBadge(code: team.code, tint: followed ? Palette.accent : nil, size: 46)
                Text(team.name).sora(.secondaryMedium).lineLimit(2).minimumScaleFactor(0.8)
                    .multilineTextAlignment(.center).padding(.horizontal, 6)
                IconView(icon: followed ? .starFill : .star, size: 14)
                    .foregroundStyle(followed ? Palette.accent : Palette.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(Palette.fill(followed ? .chip : .subtle), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.inner, style: .continuous)
                .strokeBorder(followed ? Palette.accent : Palette.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(team.name))
        .accessibilityValue(followed ? Text("Suivie") : Text("Pas suivie"))
        .accessibilityHint(followed ? Text("Ne plus suivre") : Text("Suivre"))
    }
}

/// Page 3 : « Pas de spoiler si tu veux » — la phrase, et un interrupteur par équipe choisie.
struct OnboardingSpoilerPage: View {
    let chosen: [Team]
    let spoilerFreeIds: Set<String>
    let onSetSpoilerFree: (String, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pas de spoiler si tu veux").sora(.title).tracking(Typo.titleTracking)
            HStack(alignment: .top, spacing: 10) {
                IconView(icon: .eyeOff, size: 22).foregroundStyle(Palette.accent)
                Text("L'œil cache les scores d'une équipe jusqu'à ce que tu choisisses de les voir.")
                    .sora(.body)
            }
            .glassCard(radius: Radius.inner, padding: 14)
            if chosen.isEmpty {
                Text("Tu pourras l'activer plus tard dans l'onglet Équipes.").sora(.secondary)
                    .foregroundStyle(Palette.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Masquer les scores").sora(.label).tracking(Typo.labelTracking).textCase(.uppercase)
                        .foregroundStyle(Palette.secondary)
                    ForEach(chosen) { team in
                        Toggle(isOn: Binding(get: { spoilerFreeIds.contains(team.id) },
                                             set: { onSetSpoilerFree(team.id, $0) })) {
                            HStack(spacing: 10) {
                                TeamBadge(code: team.code, size: 30)
                                Text(team.name).sora(.bodyMedium)
                            }
                        }
                        .tint(Palette.accent)
                        .frame(minHeight: 44)
                    }
                }
                .glassCard(radius: Radius.inner, padding: 12)
            }
        }
        .foregroundStyle(Palette.text)
    }
}
