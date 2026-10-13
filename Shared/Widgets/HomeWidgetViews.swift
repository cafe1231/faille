import LoLKit
import SwiftUI
import WidgetKit

/// Petit widget (spec §7, maquette ③) : le prochain match d'une équipe, teinté à sa couleur (le fond est un
/// `WidgetBackdrop` posé par l'extension). Monogrammes des deux équipes, match, jour et heure.
struct SmallWidgetView: View {
    let team: WidgetTeam?
    /// Le groupe d'apps est introuvable (`WidgetContent.appGroupMissing`) : le dire au lieu de « Aucune équipe suivie ».
    var appGroupMissing = false

    var body: some View {
        let text = WidgetText.small(team, appGroupMissing: appGroupMissing)
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(text.label)
                    .font(Sora.font(10, .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.secondary)
                Spacer(minLength: 4)
                if let team {
                    Circle()
                        .fill(Palette.team(team.team.colorHex))
                        .frame(width: 7, height: 7)
                        .shadow(color: Palette.team(team.team.colorHex), radius: 4)
                }
            }
            Spacer(minLength: 6)
            HStack(spacing: 5) {
                ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                    MonogramBadge(code: badge.code, tint: badge.tint, size: 26)
                }
            }
            .padding(.bottom, 6)
            Text(text.title)
                .font(Sora.font(17, .bold))
                .tracking(-0.5)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
            Spacer(minLength: 6)
            if let day = text.day {
                Text(day)
                    .font(Sora.font(11, .regular))
                    .foregroundStyle(Palette.secondary)
            }
            if let time = text.time {
                Text(time)
                    .font(Sora.font(15, .bold))
            }
            if let note = text.note {
                HStack(spacing: 4) {
                    if text.isMasked {
                        IconView(icon: .eyeOff, size: 11)
                    }
                    Text(note)
                        .font(Sora.font(11, .regular))
                        .lineLimit(2)
                }
                .foregroundStyle(Palette.secondary)
            }
        }
        .foregroundStyle(Palette.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Monogrammes : les deux équipes du match (couleur des équipes suivies), sinon l'équipe seule.
    private var badges: [(code: String, tint: Color?)] {
        guard let team else { return [] }
        switch team.next {
        case let .live(line), let .match(line):
            return zip(line.codes, line.colorHexes).map { (code: $0, tint: $1.map(Palette.team)) }
        case .hidden, .noMatch:
            return [(code: team.team.code, tint: Palette.team(team.team.colorHex))]
        }
    }
}

/// Moyen widget (spec §7, maquette ③) : matchs en direct, puis prochains matchs de toutes les équipes suivies.
struct MediumWidgetView: View {
    let content: WidgetContent
    static let maxRows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Mes équipes")
                    .font(Sora.font(10, .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                Spacer()
                Text(Format.day(content.date))
                    .font(Sora.font(10, .medium))
            }
            .foregroundStyle(Palette.secondary)
            if content.lines.isEmpty {
                Spacer(minLength: 0)
                Text(WidgetText.emptyMessage(content))
                    .font(Sora.font(13, .medium))
                    .foregroundStyle(Palette.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(content.lines.prefix(Self.maxRows).enumerated()), id: \.element.id) { index, line in
                    if index > 0 {
                        Divider().overlay(Color.white.opacity(0.07))
                    }
                    row(line)
                }
                Spacer(minLength: 0)
            }
        }
        .foregroundStyle(Palette.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// « ● KC 1 – 0 C9   [en direct Game 2] » ; à venir : « ● GEN vs FUR   jeu. 11:00 ».
    private func row(_ line: WidgetLine) -> some View {
        let text = WidgetText.row(line, now: content.date)
        return HStack(spacing: 6) {
            HStack(spacing: -3) {
                ForEach(Array(line.colorHexes.compactMap { $0 }.enumerated()), id: \.offset) { _, hex in
                    Circle()
                        .fill(Palette.team(hex))
                        .frame(width: 7, height: 7)
                }
            }
            Text(text.title)
                .font(Sora.font(13, .medium))
                .lineLimit(1)
            Spacer(minLength: 6)
            if text.isLive {
                HStack(spacing: 3) {
                    IconView(icon: text.isMasked ? .eyeOff : .live, size: 10)
                    Text(text.trailing)
                }
                .font(Sora.font(10, .semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.12), in: Capsule())
            } else {
                Text(text.trailing)
                    .font(Sora.font(11, .regular))
                    .foregroundStyle(Palette.secondary)
            }
        }
    }
}
