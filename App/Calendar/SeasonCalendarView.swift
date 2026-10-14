import LoLKit
import SwiftUI

/// Calendrier complet (spec saison §3.2) : vue mois des matchs du calendrier de l'appli (équipes et ligues suivies,
/// internationaux), liste du jour sous la grille (lignes anti-spoiler, révélables). Un mois hors du calendrier en cache
/// lit une page `older` / `newer` de `getSchedule` (`CalendarMonth.pageNeeded` ; ≈ 48 Ko, au rythme de la collecte),
/// gardée pour la session. Anti-spoiler I-1 : pastilles et liste du jour passent par `withoutMaskedUpcoming`.
struct SeasonCalendarView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.seasonNow) private var fixedNow
    @State private var month: Date?
    @State private var selected: Date?
    @State private var pages: [SchedulePageResult] = []
    @State private var loading = false
    @State private var haptics = HapticTrigger()
    @ReduceMotion var reduceMotion

    private var calendar: Calendar { .current }

    var body: some View {
        let now = fixedNow ?? Date()
        let shownMonth = month ?? now
        let all = CalendarEvents.merged(pages: pages, schedule: store.schedule, live: store.live)
        // Calculé une fois par rendu (I-1) : l'ensemble masqué n'est pas recalculé par ligne.
        let events = store.withoutMaskedUpcoming(all)
        let days = CalendarMonth.days(events: events, month: shownMonth, calendar: calendar,
                                      followed: HomeFeed.followedMatchIds(events, follows: store.follows), now: now)
        let day = selected ?? now
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { move(-1, from: shownMonth) } label: {
                        IconView(icon: .back, size: 18).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Mois précédent"))
                    Spacer()
                    Text(shownMonth.formatted(.dateTime.month(.wide).year())).sora(.headline)
                    Spacer()
                    Button { move(1, from: shownMonth) } label: {
                        IconView(icon: .arrow, size: 18).frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text("Mois suivant"))
                }
                .buttonStyle(.pressable)
                .foregroundStyle(Palette.text)
                MonthGrid(days: days, calendar: calendar, selected: $selected, onHaptic: { haptics.play($0) })
                    .glassCard(radius: Radius.inner, padding: 12)
                if loading {
                    SeasonSkeletonCard(lines: 2, label: String(localized: "Calendrier en chargement"))
                } else if store.season.stopReason != nil,
                          CalendarMonth.pageNeeded(for: shownMonth, events: all, calendar: calendar) != nil {
                    NoteCard(icon: .off, text: String(localized: "Réseau indisponible, réessaie plus tard"))
                }
                let list = CalendarMonth.events(on: day, in: events, calendar: calendar)
                SectionLabel(text: day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                if list.isEmpty {
                    NoteCard(icon: .calendar, text: String(localized: "Aucun match ce jour-là"))
                } else {
                    VStack(spacing: 2) {
                        ForEach(list) { event in
                            MatchLine(event: event, onReveal: reveal)
                        }
                    }
                    .glassCard(radius: Radius.inner, padding: 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .abyssBackground()
        .navigationTitle(String(localized: "Calendrier"))
        .navigationBarTitleDisplayMode(.inline)
        .haptics(haptics)
        .task(id: month) { await loadIfNeeded(shownMonth) }
    }

    private func move(_ delta: Int, from current: Date) {
        haptics.play(.gamePicked)
        withAnimation(Motion.animation(.snappy, reduceMotion: reduceMotion)) {
            month = calendar.date(byAdding: .month, value: delta, to: current)
            selected = nil
        }
    }

    /// Mois hors du calendrier connu : la page 0 (pour ses jetons), puis `older` / `newer` jusqu'à le couvrir (3 pages au
    /// plus par mois demandé ; aucune quand `newer` est nil : rien de plus récent).
    private func loadIfNeeded(_ month: Date) async {
        let ids = ScheduleQuery.leagueIds(follows: store.follows, leagues: store.leagues)
        var attempts = 0
        while attempts < 3, let direction = CalendarMonth.pageNeeded(
            for: month, events: CalendarEvents.merged(pages: pages, schedule: store.schedule, live: store.live),
            calendar: calendar) {
            attempts += 1
            loading = true
            defer { loading = false }
            if pages.isEmpty {
                guard let first = await store.season.schedulePage(leagueIds: ids, token: nil) else { return }
                pages.append(first)
                continue
            }
            guard let token = CalendarEvents.token(direction, pages: pages),
                  let page = await store.season.schedulePage(leagueIds: ids, token: token) else { return }
            pages.append(page)
        }
    }

    private func reveal(_ matchId: String) {
        haptics.play(.reveal)
        withAnimation(Motion.animation(.reveal, reduceMotion: reduceMotion)) { store.reveal(matchId: matchId) }
    }
}
