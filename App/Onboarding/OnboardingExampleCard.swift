import SwiftUI

/// Exemple vivant du premier écran (spec saison §3.7) : une carte Vitrail d'aperçu, étiquetée « Exemple », dont le chrono
/// et les kills avancent (une seconde par seconde, un kill toutes les 6 s) ; figée sous « Réduire les animations ». Rien
/// de réel : aucune donnée, aucune requête.
struct OnboardingExampleCard: View {
    @ReduceMotion var reduceMotion
    /// Départ du chrono d'exemple : 18:42 de jeu.
    private static let clockStart: TimeInterval = 18 * 60 + 42

    var body: some View {
        if Motion.runs(.livePulse, reduceMotion: reduceMotion) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                card(elapsed: context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 120))
            }
        } else {
            card(elapsed: 0)
        }
    }

    private func card(elapsed: TimeInterval) -> some View {
        let clock = Int(Self.clockStart + elapsed)
        let kills = 7 + Int(elapsed / 6) % 4
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Mondial · Play-in · Bo5").font(Typo.secondary).foregroundStyle(Palette.secondary)
                Spacer()
                Chip { Text("Exemple") }
            }
            HStack(spacing: 8) {
                TeamBadge(code: "KC", tint: Palette.accent, size: 34)
                Text("KC").font(Typo.headline)
                Spacer()
                Text("1 – 0").font(Typo.scoreLarge).monospacedDigit()
                Spacer()
                Text("C9").font(Typo.headline)
                TeamBadge(code: "C9", size: 34)
            }
            HStack(spacing: 14) {
                Chip {
                    IconView(icon: .live, size: 12)
                    Text("Game 2 · \(clock / 60):\(String(format: "%02d", clock % 60))").monospacedDigit()
                }
                Label { Text("\(kills)").monospacedDigit() } icon: { IconView(icon: .swords, size: 13) }
                Label { Text("+2,1 k").monospacedDigit() } icon: { IconView(icon: .gold, size: 13) }
                Label { Text("3").monospacedDigit() } icon: { IconView(icon: .tower, size: 13) }
            }
            .font(Typo.secondaryMedium)
        }
        .foregroundStyle(Palette.text)
        .glassCard(tint: Palette.accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Exemple de carte : Karmine Corp 1, Cloud9 0, game 2 en direct"))
    }
}
