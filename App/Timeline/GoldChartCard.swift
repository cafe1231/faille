import Charts
import LoLKit
import SwiftUI

/// Courbe de l'écart de gold (spec fonctionnalités §5), Swift Charts : au-dessus de zéro quand l'équipe de gauche mène, à
/// sa couleur ; en dessous quand c'est l'autre, à la sienne ; repères des drakes et des barons du fil. En direct, elle
/// s'allonge à chaque frame. N'existe que pour un match non masqué.
struct GoldChartCard: View {
    /// Écart réorienté vers l'équipe de gauche (`TimelineStore.goldPoints(gameId:orientedTo:)`).
    let points: [GoldPoint]
    /// Drakes et barons du fil (`TimelineText.isMarker`).
    let markers: [TimelineEvent]
    /// Les deux équipes, dans l'ordre d'affichage (gauche = au-dessus de zéro).
    let teams: [TimelineTeam]
    var loading = false

    /// Hauteur de la courbe (et de son gabarit).
    static let height: CGFloat = 150

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatLabel(icon: .gold, text: String(localized: "Écart de gold"))
                Spacer(minLength: 8)
                if let last = points.last, let leader = leaderText(last.difference) {
                    Text(leader)
                        .sora(.secondaryMedium)
                        .foregroundStyle(last.difference >= 0 ? tint(0) : tint(1))
                        .monospacedDigit()
                        .numericChange(last.difference)
                }
            }
            if points.count >= 2 {
                chart
                    .frame(height: Self.height)
            } else if loading {
                SkeletonBlock(height: Self.height, radius: 12)
            } else {
                Text("La courbe se dessine après quelques minutes de jeu")
                    .sora(.secondary)
                    .foregroundStyle(Palette.secondary)
            }
        }
        .foregroundStyle(Palette.text)
        .glassCard(radius: Radius.inner, padding: 14)
    }

    private func tint(_ index: Int) -> Color {
        teams.indices.contains(index) ? teams[index].tint : Palette.secondary
    }

    /// « KC +2,1k » ; « Égalité » à zéro.
    private func leaderText(_ difference: Int) -> String? {
        guard teams.count == 2 else { return nil }
        if difference == 0 { return "Égalité" }
        return "\(teams[difference > 0 ? 0 : 1].code) +\(Format.gold(abs(difference)))"
    }

    private var chart: some View {
        let data = GoldChartData.withZeroCrossings(points)
        let limit = GoldChartData.axisLimit(points)
        return Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { _, point in
                AreaMark(x: .value("Temps", point.gameTime), yStart: .value("Base", 0),
                         yEnd: .value("Écart", max(0, point.difference)))
                    .foregroundStyle(by: .value("Équipe", "gauche"))
                AreaMark(x: .value("Temps", point.gameTime), yStart: .value("Base", 0),
                         yEnd: .value("Écart", min(0, point.difference)))
                    .foregroundStyle(by: .value("Équipe", "droite"))
                LineMark(x: .value("Temps", point.gameTime), y: .value("Écart", point.difference))
                    .foregroundStyle(Palette.text.opacity(0.85))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            RuleMark(y: .value("Égalité", 0))
                .foregroundStyle(Palette.glassBorder)
                .lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(Array(markers.enumerated()), id: \.offset) { _, event in
                RuleMark(x: .value("Temps", event.gameTime))
                    .foregroundStyle(Palette.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, spacing: 2) {
                        IconView(icon: TimelineCard.icon(event.kind), size: 10)
                            .foregroundStyle(teams.first { $0.id == event.teamId }?.tint ?? Palette.secondary)
                    }
            }
        }
        .chartForegroundStyleScale(domain: ["gauche", "droite"], range: [tint(0).opacity(0.45), tint(1).opacity(0.45)])
        .chartLegend(.hidden)
        .chartYScale(domain: -limit...limit)
        .chartXAxis {
            AxisMarks(values: .stride(by: 600)) { value in
                AxisGridLine().foregroundStyle(Palette.glassBorder.opacity(0.4))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text("\(Int(seconds / 60))'")
                            .sora(.label)
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [-limit, 0, limit]) { value in
                AxisGridLine().foregroundStyle(Palette.glassBorder.opacity(0.4))
                AxisValueLabel {
                    if let gold = value.as(Int.self) {
                        Text(Format.goldDiff(gold))
                            .sora(.label)
                            .foregroundStyle(Palette.secondary)
                    }
                }
            }
        }
        .accessibilityLabel(leaderText(points.last?.difference ?? 0).map { "Écart de gold : \($0)" } ?? "Écart de gold")
    }
}
