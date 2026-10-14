import LoLKit
import SwiftUI

/// Grille d'un mois (spec saison §3.2) : semaines entières de `CalendarMonth.days` (lundi en premier en France), jours
/// hors du mois estompés, pastille pleine = match suivi, anneau = international ; le jour choisi en blanc.
struct MonthGrid: View {
    let days: [CalendarDay]
    let calendar: Calendar
    @Binding var selected: Date?
    let onHaptic: (Haptic) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
            ForEach(Array(Self.weekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                Text(symbol).sora(.label).foregroundStyle(Palette.secondary)
            }
            ForEach(days) { day in
                cell(day)
            }
        }
    }

    private func cell(_ day: CalendarDay) -> some View {
        let isSelected = selected.map { calendar.isDate($0, inSameDayAs: day.date) } ?? day.isToday
        return Button {
            if !isSelected { onHaptic(.gamePicked) }
            selected = day.date
        } label: {
            VStack(spacing: 3) {
                Text("\(day.dayNumber)").sora(.bodyMedium).monospacedDigit()
                switch day.marker {
                case .followed: Circle().fill(Palette.accent).frame(width: 5, height: 5)
                case .international: Circle().strokeBorder(Palette.accent, lineWidth: 1).frame(width: 5, height: 5)
                case .none: Color.clear.frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(isSelected ? Palette.abyss : Palette.text)
            .opacity(day.isInMonth ? 1 : 0.35)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? Color.white.opacity(0.92) : .clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(Text(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))))
        .accessibilityValue(day.marker == .none ? Text("") : Text("Matchs suivis"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Initiales des jours, dans l'ordre de la locale (`firstWeekday`).
    static func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}
