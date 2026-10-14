import SwiftUI

/// Exemple vivant du premier écran (spec saison §3.7) : une carte Vitrail d'aperçu, étiquetée « Exemple », dont le chrono,
/// les kills et le score avancent (le chrono seconde par seconde, un kill toutes les 6 s, une game gagnée toutes les
/// 30 s : 0 – 0, 1 – 0, 1 – 1, 2 – 1) ; figée sous « Réduire les animations » (1 – 0, game 2). Rien de réel : deux
/// équipes FICTIVES (jamais l'affiche d'un vrai match), aucune donnée, aucune requête.
struct OnboardingExampleCard: View {
    @ReduceMotion var reduceMotion
    /// Départ du chrono d'exemple : 18:42 de jeu.
    private static let clockStart: TimeInterval = 18 * 60 + 42
    /// Durée de chaque game d'exemple, en secondes de la boucle.
    private static let gameSpan: TimeInterval = 30
    /// Scores de la série d'exemple, game après game (équipe de gauche, équipe de droite).
    static let series: [(left: Int, right: Int)] = [(0, 0), (1, 0), (1, 1), (2, 1)]

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
        // Réduire les animations : `elapsed` = 0 → 1 – 0, game 2 (la carte figée montre une série en cours).
        let phase = (1 + Int(elapsed / Self.gameSpan)) % Self.series.count
        let score = Self.series[phase]
        let clock = Int(Self.clockStart + elapsed.truncatingRemainder(dividingBy: Self.gameSpan))
        let kills = 7 + Int(elapsed / 6) % 4
        let game = phase + 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Compétition d'exemple · Bo5").font(Typo.secondary).foregroundStyle(Palette.secondary)
                Spacer()
                Chip { Text("Exemple") }
            }
            HStack(spacing: 8) {
                TeamBadge(code: "AUR", tint: Palette.accent, size: 34)
                Text("AUR").font(Typo.headline)
                Spacer()
                Text("\(score.left) – \(score.right)").font(Typo.scoreLarge).monospacedDigit()
                Spacer()
                Text("ZYX").font(Typo.headline)
                TeamBadge(code: "ZYX", size: 34)
            }
            HStack(spacing: 14) {
                Chip {
                    IconView(icon: .live, size: 12)
                    Text("Game \(game) · \(clock / 60):\(String(format: "%02d", clock % 60))").monospacedDigit()
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
        .accessibilityLabel(Text("Exemple de carte : Aurore \(score.left), Zénith \(score.right), game \(game) en direct"))
    }
}
