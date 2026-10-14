import LoLKit
import SwiftUI

/// Onglet Accueil (spec saison §2) : en-tête, « Suis tes équipes » (sans suivi), « À ne pas rater », « En direct
/// maintenant », calendrier de la semaine, résultats récents, activité, joueurs en forme. Tout vient des stores (cache
/// d'abord) ; les sections sont calculées hors du fil principal (`HomeModel.compute`), une fois par `HomeKey`. Cascade
/// d'apparition une fois ; aucune animation continue hors de la section « En direct ».
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.seasonNow) private var fixedNow
    /// Espace de noms du zoom carte → Détail (`RootView`) ; nil (aperçus Xcode) : pas de zoom.
    var zoom: Namespace.ID? = nil
    /// Aller à l'onglet Équipes (carte « Suis tes équipes »).
    let openTeams: () -> Void
    @State private var content: HomeContent?
    @State private var selectedDay: Date?
    @State private var hotKey = HotPlayersKey(period: .week, metric: .kda)
    @State private var haptics = HapticTrigger()
    @State private var cascaded = false
    /// Dernière publication de `content` (M16 : au plus une toutes les 30 s pendant la collecte).
    @State private var lastPublished: Date?
    /// Clé de la dernière publication : le délai ne retient que les ticks de lecture de games (`shouldThrottle`).
    @State private var lastKey: HomeKey?
    @ReduceMotion var reduceMotion

    var body: some View {
        let now = fixedNow ?? Date()
        let calendar = Calendar.current
        let shown = cascaded || !Motion.runs(.cascade, reduceMotion: reduceMotion)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(String(localized: "Accueil"),
                             subtitle: HomeTexts.subtitle(now: now, todayCount: content?.sections.todayCount ?? 0))
                if let banner = store.bannerText {
                    ErrorBanner(text: banner).transition(Motion.bannerTransition(reduceMotion: reduceMotion))
                }
                // M7 : avec un « aujourd'hui » fixé (aperçus, tests), le premier état est calculé tout de suite, de
                // façon synchrone ; l'appli calcule hors du fil principal et montre des squelettes jusque-là.
                if let shownContent = content ?? (fixedNow == nil ? nil
                                                  : HomeModel.compute(store.homeInputs(now: now, calendar: calendar))) {
                    sections(shownContent, now: now, calendar: calendar, shown: shown)
                } else {
                    SeasonSkeletonCard(lines: 3, label: String(localized: "Accueil en chargement"))
                    SeasonSkeletonCard(lines: 2, label: String(localized: "Accueil en chargement"))
                }
            }
            .animation(Motion.animation(.snappy, reduceMotion: reduceMotion), value: store.isFailing)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await refresh() }
        .haptics(haptics)
        .onAppear { cascaded = true }
        .task(id: key(now: now, calendar: calendar)) {
            // M16 : pendant une passe de collecte, au plus une publication toutes les 30 s pour les games lues ; un
            // suivi, une révélation ou un changement de jour se publie sans attendre (anti-spoiler).
            let taskKey = key(now: now, calendar: calendar)
            if HomeKey.shouldThrottle(old: lastKey, new: taskKey, running: store.season.progress.running),
               let last = lastPublished {
                let wait = 30 - Date().timeIntervalSince(last)
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled else { return }
            }
            let inputs = store.homeInputs(now: now, calendar: calendar)
            let computed = await Task.detached(priority: .userInitiated) { HomeModel.compute(inputs) }.value
            guard !Task.isCancelled else { return }
            content = computed
            lastPublished = Date()
            lastKey = taskKey
        }
        .abyssBackground()
        .navigationTitle(String(localized: "Accueil"))
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private func sections(_ content: HomeContent, now: Date, calendar: Calendar, shown: Bool) -> some View {
        if !content.hasFollows {
            FollowPromptCard(action: openTeams).cascadeIn(index: 0, shown: shown)
        }
        MustWatchSection(picks: content.sections.mustWatch).cascadeIn(index: 1, shown: shown)
        LiveNowSection(items: content.live, onHaptic: { haptics.play($0) }).cascadeIn(index: 2, shown: shown)
        WeekStripSection(days: content.strip, eventsByDay: content.eventsByDay, today: calendar.startOfDay(for: now),
                         calendar: calendar, selected: $selectedDay, onReveal: reveal,
                         onHaptic: { haptics.play($0) })
            .cascadeIn(index: 3, shown: shown)
        RecentResultsSection(events: content.sections.recentResults, onReveal: reveal).cascadeIn(index: 4, shown: shown)
        ActivitySection(items: content.sections.activity, loading: !content.isLoaded).cascadeIn(index: 5, shown: shown)
        HotPlayersSection(players: content.hotPlayers, progress: content.progress, key: $hotKey,
                          onHaptic: { haptics.play($0) })
            .cascadeIn(index: 6, shown: shown)
    }

    private func key(now: Date, calendar: Calendar) -> HomeKey {
        HomeKey(version: store.season.version, follows: store.follows, revealed: store.settings.revealedMatchIds,
                day: calendar.startOfDay(for: now), updated: store.lastUpdate, liveIds: store.live?.map(\.id),
                loaded: store.season.isLoaded, running: store.season.progress.running,
                revealedStandings: store.settings.revealedStandingIds)
    }

    /// « Toucher pour révéler » (spec §8) : retour haptique et fondu de révélation.
    private func reveal(_ matchId: String) {
        haptics.play(.reveal)
        withAnimation(Motion.animation(.reveal, reduceMotion: reduceMotion)) {
            store.reveal(matchId: matchId)
        }
    }

    private func refresh() async {
        await store.refreshNow()
        guard !Task.isCancelled else { return }
        haptics.play(store.isFailing ? .refreshFailed : .refreshSucceeded)
    }
}

/// Sans équipe suivie (spec saison §2.2) : l'Accueil montre quand même le Mondial, avec cette carte en tête.
struct FollowPromptCard: View {
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suis tes équipes pour un accueil sur mesure").sora(.headline)
            Text("En attendant, voici le Mondial.").sora(.secondary).foregroundStyle(Palette.secondary)
            Button(action: action) {
                HStack(spacing: 6) {
                    IconView(icon: .star, size: 15)
                    Text("Choisir mes équipes")
                }
                .sora(.bodyMedium)
                .foregroundStyle(Palette.abyss)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Palette.accent, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .foregroundStyle(Palette.text)
        .glassCard()
    }
}
