import LoLKit
import SwiftUI

/// Premier lancement (spec saison §3.7) : 3 écrans, « Passer » partout, points de pagination, glissement d'une page à
/// l'autre (`Motion.snappy` ; fondu sous « Réduire les animations »). Vue à fermetures : elle ne connaît pas `AppStore`
/// (I2 la branche en `fullScreenCover`). « C'est parti » ou « Passer » → `onDone` (Accueil).
struct OnboardingView: View {
    let teams: [Team]
    let leagues: [League]
    /// Équipes suivies (du catalogue), pour les étoiles de la page 2 et les interrupteurs de la page 3.
    let followedTeams: [Team]
    let followedLeagueIds: Set<String>
    let spoilerFreeIds: Set<String>
    let search: (String) -> [Team]
    let onToggleTeam: (Team) -> Void
    let onToggleLeague: (League) -> Void
    let onSetSpoilerFree: (String, Bool) -> Void
    let onDone: () -> Void
    @State private var page: Int
    @State private var haptics = HapticTrigger()
    @ReduceMotion var reduceMotion

    init(teams: [Team], leagues: [League], followedTeams: [Team], followedLeagueIds: Set<String>,
         spoilerFreeIds: Set<String>, search: @escaping (String) -> [Team], onToggleTeam: @escaping (Team) -> Void,
         onToggleLeague: @escaping (League) -> Void, onSetSpoilerFree: @escaping (String, Bool) -> Void,
         onDone: @escaping () -> Void, initialPage: Int = 0) {
        self.teams = teams
        self.leagues = leagues
        self.followedTeams = followedTeams
        self.followedLeagueIds = followedLeagueIds
        self.spoilerFreeIds = spoilerFreeIds
        self.search = search
        self.onToggleTeam = onToggleTeam
        self.onToggleLeague = onToggleLeague
        self.onSetSpoilerFree = onSetSpoilerFree
        self.onDone = onDone
        _page = State(initialValue: min(max(initialPage, 0), 2))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if page > 0 {
                    Button { go(page - 1) } label: {
                        HStack(spacing: 6) {
                            IconView(icon: .back, size: 16)
                            Text("Retour").font(Typo.bodyMedium)
                        }
                        .foregroundStyle(Palette.secondary)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(Text("Retour"))
                    .accessibilityHint(Text("Page précédente"))
                }
                Spacer()
                Button(action: onDone) {
                    Text("Passer").font(Typo.bodyMedium).foregroundStyle(Palette.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 16)
            ScrollView {
                Group {
                    switch page {
                    case 0:
                        OnboardingWelcomePage()
                    case 1:
                        OnboardingPickPage(teams: teams, leagues: leagues, followedTeamIds: followedTeamIds,
                                           followedLeagueIds: followedLeagueIds, search: search,
                                           onToggleTeam: toggle, onToggleLeague: toggle)
                    default:
                        OnboardingSpoilerPage(chosen: followedTeams, spoilerFreeIds: spoilerFreeIds, onSetSpoilerFree: { id, on in
                            haptics.play(.spoilerToggle)
                            onSetSpoilerFree(id, on)
                        })
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                                    removal: .opacity))
            }
            .gesture(DragGesture(minimumDistance: 30).onEnded { value in
                if value.translation.width < -60 { go(page + 1) }
                if value.translation.width > 60 { go(page - 1) }
            })
            footer
        }
        .abyssBackground()
        .haptics(haptics)
    }

    private var followedTeamIds: Set<String> {
        Set(followedTeams.map(\.id))
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index == page ? Palette.accent : Color.white.opacity(0.2))
                        .frame(width: 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Page \(page + 1) sur 3"))
            Button { page == 2 ? onDone() : go(page + 1) } label: {
                Group {
                    if page == 2 { Text("C'est parti") } else { Text("Continuer") }
                }
                .font(Typo.bodyMedium)
                .foregroundStyle(Palette.abyss)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Palette.accent, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private func go(_ target: Int) {
        guard (0...2).contains(target), target != page else { return }
        withAnimation(Motion.animation(.snappy, reduceMotion: reduceMotion)) { page = target }
    }

    private func toggle(_ team: Team) {
        haptics.play(followedTeamIds.contains(team.id) ? .unfollow : .follow)
        onToggleTeam(team)
    }

    private func toggle(_ league: League) {
        haptics.play(followedLeagueIds.contains(league.id) ? .unfollow : .follow)
        onToggleLeague(league)
    }
}
