import LoLKit
import SwiftUI

// MARK: - Écran verrouillé (spec §6.1, §6.3, maquettes ① et ②)

/// Fond de la Live Activity : dégradé à 160° de la couleur de l'équipe suivie vers l'abysse ; verre neutre si aucune
/// équipe du match n'est suivie (match épinglé à la main). Un dégradé seulement : pas de matière dans une Live Activity.
struct LiveActivityBackdrop: View {
    let tintHex: String?

    var body: some View {
        let top = tintHex.map { Palette.team($0).opacity(0.34) } ?? Color.white.opacity(0.08)
        ZStack {
            Palette.abyss
            LinearGradient(
                stops: [.init(color: top, location: 0), .init(color: Palette.abyss.opacity(0.86), location: 0.7)],
                startPoint: UnitPoint(x: 0.33, y: 0),
                endPoint: UnitPoint(x: 0.67, y: 1)
            )
        }
    }
}

/// La Live Activity de l'écran verrouillé : « LIGUE · Bo5 · Game N » et chrono, score entre les deux monogrammes,
/// 5 lignes de stats ou un message. iOS tronque au-delà de 160 pt de haut : vérifié par les tests hébergés.
struct LiveActivityLockView: View {
    let display: LiveActivityDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Text(display.header)
                    .font(Sora.font(9.5, .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.secondary)
                    // Un nom de ligue long (« Prime League Pro Division ») rétrécit puis se tronque au milieu : la fin
                    // (« Bo3 · Game 2 ») reste lisible, et l'état à droite garde toute sa place.
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                LiveActivityStatusView(status: display.status)
                    .font(Sora.font(11.5, .semibold))
                    .layoutPriority(1)
            }
            LiveActivityScoreRow(display: display)
            if !display.rows.isEmpty {
                LiveActivityStatRows(rows: display.rows, teams: display.teams)
                    .opacity(display.faded ? 0.55 : 1)
            }
            if let message = display.message {
                LiveActivityMessageView(message: message)
                    .padding(.top, 2)
            }
        }
        .foregroundStyle(Palette.text)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LiveActivityBackdrop(tintHex: display.tintHex))
    }
}

/// Droite de l'en-tête : chrono natif (il tourne sans mise à jour), chrono figé, « En direct », « entre deux games »,
/// « Victoire KC », « Terminé », ou « màj il y a X minutes » quand la Live Activity n'est plus fraîche (spec §6.3).
struct LiveActivityStatusView: View {
    let status: LiveActivityDisplay.Status
    /// « Game 2 · » devant le chrono (Dynamic Island déployée).
    var prefix: String? = nil
    /// Largeur réservée au chrono qui tourne : fixe (il ne saute pas quand il gagne un chiffre), de quoi écrire
    /// « 1:02:05 » à la taille du texte voisin. Le chrono s'y aligne à droite, collé au bord de l'en-tête.
    var timerWidth: CGFloat = 48

    var body: some View {
        HStack(spacing: 4) {
            IconView(icon: icon, size: 12)
            switch status {
            case let .clock(.running(since)):
                if let prefix {
                    Text(prefix)
                }
                // Largeur fixe : un minuteur natif occupe sinon toute la place disponible.
                Text(since, style: .timer)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(width: timerWidth, alignment: .trailing)
            case let .clock(.stopped(text)):
                if let prefix {
                    Text(prefix)
                }
                Text(text)
                    .monospacedDigit()
                    .numericTransition()
            case let .stale(since):
                // « màj il y a 9 minutes », sans les secondes que donne `.relative` : le format de référence d'iOS,
                // limité à une unité (minutes, puis heures), écrit lui-même « il y a » (d'où le `label` du statut :
                // « màj » seul, une seule fois) et se met à jour sans relance de la Live Activity. Comme un minuteur
                // natif, il occupe toute la largeur proposée : largeur fixe, de quoi écrire « màj il y a 59 minutes »,
                // alignée à droite pour que le bord de l'en-tête reste net.
                Text("\(status.label ?? "") \(Text(.currentDate, format: .reference(to: since, allowedFields: [.hour, .minute], maxFieldCount: 1)))")
                    .multilineTextAlignment(.trailing)
                    .frame(width: 124, alignment: .trailing)
            default:
                Text(status.label ?? "")
            }
        }
        .lineLimit(1)
        .foregroundStyle(isStale ? Palette.secondary : Palette.text)
    }

    private var isStale: Bool {
        if case .stale = status { return true }
        return false
    }

    /// La nature d'une info se lit à son icône (spec §9).
    private var icon: Icon {
        switch status {
        case .clock, .live: return .live
        case .betweenGames: return .pause
        case .victory: return .trophy
        case .finished: return .check
        case .stale: return .refresh
        }
    }
}

/// « [KC] KC   1 – 0   C9 [C9] » ; « vs » sans score (masqué). Le centre est fixe et chaque côté prend la même
/// largeur : le score est exactement centré, quelle que soit la largeur des codes d'équipe.
struct LiveActivityScoreRow: View {
    let display: LiveActivityDisplay

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 7) {
                if let left = display.teams.first {
                    MonogramBadge(code: left.code, tint: left.colorHex.map(Palette.team), size: 24)
                    Text(left.code)
                        .font(Sora.font(15, .semibold))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let score = display.score, score.count == 2 {
                // Score non masqué (`display.score` est nil pour un match masqué) : ses chiffres défilent d'une mise à
                // jour à l'autre (spec finitions §4).
                Text(Format.score(score))
                    .font(Sora.font(22, .bold))
                    .monospacedDigit()
                    .numericTransition()
            } else {
                Text("vs")
                    .font(Sora.font(12, .medium))
                    .foregroundStyle(Palette.secondary)
            }
            HStack(spacing: 7) {
                if display.teams.count > 1 {
                    Text(display.teams[1].code)
                        .font(Sora.font(15, .semibold))
                        .lineLimit(1)
                    MonogramBadge(code: display.teams[1].code, tint: display.teams[1].colorHex.map(Palette.team), size: 24)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

/// Les 5 lignes de stats (spec §6.1) : « 7 · KILLS · 4 », une icône d'épées devant le libellé ; l'écart de gold à la
/// couleur de l'équipe qui mène.
struct LiveActivityStatRows: View {
    let rows: [LiveActivityDisplay.Row]
    let teams: [LiveActivityDisplay.Side]

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 1) {
            ForEach(rows, id: \.stat) { row in
                GridRow {
                    HStack(spacing: 4) {
                        Text(row.left)
                        if row.leader == 0, let lead = row.lead {
                            leadText(lead, leader: 0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        IconView(icon: row.stat.icon, size: 11)
                        Text(row.stat.label)
                            .font(Sora.font(8.5, .semibold))
                            .tracking(0.7)
                            .textCase(.uppercase)
                    }
                    .foregroundStyle(Palette.secondary)
                    .frame(minWidth: 84)
                    HStack(spacing: 4) {
                        if row.leader == 1, let lead = row.lead {
                            leadText(lead, leader: 1)
                        }
                        Text(row.right)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .font(Sora.font(11.5, .bold))
        .monospacedDigit()
        .numericTransition()
    }

    private func leadText(_ text: String, leader: Int) -> some View {
        let color = teams.indices.contains(leader) ? teams[leader].colorHex.map(Palette.team) : nil
        return Text(text)
            .font(Sora.font(9, .semibold))
            .foregroundStyle(color ?? Palette.secondary)
    }
}

/// Message sous le score (spec §6.3, §8) : anti-spoiler, prochaine game, stats indisponibles, fin de match.
struct LiveActivityMessageView: View {
    let message: LiveActivityDisplay.Message

    var body: some View {
        HStack(spacing: 5) {
            if let icon = message.icon {
                IconView(icon: icon, size: 12)
            }
            Text(message.text)
            if let accent = message.accent {
                Text(accent)
                    .font(Sora.font(11, .semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .font(Sora.font(11, .regular))
        .foregroundStyle(Palette.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity)
    }
}

extension LiveActivityDisplay.Stat {
    /// Icône de chaque stat (spec §9 : kills = épées, gold = pièces, tour, drake = flamme, baron = hexagone).
    var icon: Icon {
        switch self {
        case .kills: return .swords
        case .gold: return .gold
        case .towers: return .tower
        case .drakes: return .drake
        case .barons: return .baron
        }
    }
}

extension LiveActivityDisplay.Message {
    var icon: Icon? {
        switch self {
        case .masked: return .eyeOff
        case .nextGame: return .clock
        case .statsUnavailable: return .off
        case .statsPending: return .refresh
        case .leavingSoon: return nil
        }
    }
}
