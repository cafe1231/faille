import LoLKit
import SwiftUI

/// Bandeau du calendrier (spec saison §2.2) : 7 jours à l'écran (aujourd'hui − 1 → + 5), ± 3 semaines en défilant ;
/// pastille pleine = match d'une équipe ou ligue suivie, anneau = international. Toucher un jour → ses matchs (lignes
/// anti-spoiler) ; « Tout le calendrier » → vue mois.
struct WeekStripSection: View {
    let days: [CalendarDay]
    let eventsByDay: [Date: [MatchEvent]]
    let today: Date
    let calendar: Calendar
    @Binding var selected: Date?
    let onReveal: (String) -> Void
    let onHaptic: (Haptic) -> Void

    var body: some View {
        let day = selected ?? today
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: String(localized: "Calendrier"))
                NavigationLink(value: CalendarRoute()) {
                    Text("Tout le calendrier").sora(.label).foregroundStyle(Palette.accent).frame(minHeight: 44)
                }
                .buttonStyle(.pressable)
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(days) { cell in
                            dayCell(cell, selected: calendar.isDate(cell.date, inSameDayAs: day))
                                .id(cell.date)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    if let start = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today)) {
                        proxy.scrollTo(start, anchor: .leading)
                    }
                }
            }
            let events = eventsByDay[calendar.startOfDay(for: day)] ?? []
            if events.isEmpty {
                Text("Aucun match ce jour-là").sora(.secondary).foregroundStyle(Palette.secondary)
            } else {
                ForEach(events) { event in
                    MatchLine(event: event, onReveal: onReveal)
                }
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 12)
    }

    private func dayCell(_ cell: CalendarDay, selected: Bool) -> some View {
        Button {
            if !selected { onHaptic(.gamePicked) }
            self.selected = cell.date
        } label: {
            VStack(spacing: 4) {
                Text(cell.date.formatted(.dateTime.weekday(.abbreviated))).sora(.label)
                Text("\(cell.dayNumber)").sora(.headline).monospacedDigit()
                dot(cell.marker)
            }
            .foregroundStyle(selected ? Palette.abyss : Palette.text)
            .frame(width: 44, height: 64)
            .background(selected ? Color.white.opacity(0.92) : Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(cell.date.formatted(.dateTime.weekday(.wide).day().month(.wide))))
        .accessibilityValue(cell.marker == .none ? Text("") : Text("Matchs suivis"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private func dot(_ marker: DayMarker) -> some View {
        switch marker {
        case .followed: Circle().fill(Palette.accent).frame(width: 6, height: 6)
        case .international: Circle().strokeBorder(Palette.accent, lineWidth: 1.2).frame(width: 6, height: 6)
        case .none: Color.clear.frame(width: 6, height: 6)
        }
    }
}
