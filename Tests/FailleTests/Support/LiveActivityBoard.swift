import LoLKit
import SwiftUI
import UIKit
@testable import Faille

/// Un état de la Live Activity sur une planche : sa légende et ce qu'elle affiche.
struct LiveBoardState {
    let caption: String
    let display: LiveActivityDisplay

    /// Écran verrouillé : chaque état de la spec §6.3 (maquettes ① et ②).
    static var lockScreen: [LiveBoardState] {
        [
            LiveBoardState(caption: "En jeu · KC", display: LiveActivitySamples.inGame),
            LiveBoardState(caption: "Game en pause · chrono figé", display: LiveActivitySamples.clockStopped),
            LiveBoardState(caption: "Anti-spoiler · T1", display: LiveActivitySamples.masked),
            LiveBoardState(caption: "Pas fraîche", display: LiveActivitySamples.stale),
            LiveBoardState(caption: "Entre deux games", display: LiveActivitySamples.betweenGames),
            LiveBoardState(caption: "Fin du match", display: LiveActivitySamples.finished),
            LiveBoardState(caption: "Stats indisponibles", display: LiveActivitySamples.statsUnavailable),
        ]
    }

    /// Noms de ligue longs : mesurés et dessinés comme les états de l'écran verrouillé, mais pas sur la planche, qui est
    /// pleine.
    static var longLeague: [LiveBoardState] {
        [
            LiveBoardState(caption: "Ligue au nom long · entre deux games", display: LiveActivitySamples.longLeagueBetweenGames),
            LiveBoardState(caption: "Ligue au nom long · pas fraîche", display: LiveActivitySamples.longLeagueStale),
        ]
    }

    /// Tous les états de l'écran verrouillé que les tests de hauteur et de dessin parcourent.
    static var lockScreenChecked: [LiveBoardState] {
        lockScreen + longLeague
    }

    /// Dynamic Island : en jeu, anti-spoiler, fin du match.
    static var island: [LiveBoardState] {
        [
            LiveBoardState(caption: "En jeu · KC", display: LiveActivitySamples.inGame),
            LiveBoardState(caption: "Anti-spoiler · T1", display: LiveActivitySamples.masked),
            LiveBoardState(caption: "Fin du match", display: LiveActivitySamples.finished),
        ]
    }
}

/// Planche de l'écran verrouillé (spec §6.3) : la Live Activity dans chaque état, coins arrondis comme iOS la pose.
struct LiveActivityBoard: View {
    let states: [LiveBoardState]
    static let size = CGSize(width: WidgetSize.screen.width, height: 1120)
    /// Largeur d'une Live Activity sur un iPhone de 6,3 pouces.
    static let activityWidth: CGFloat = 370

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                VStack(alignment: .leading, spacing: 6) {
                    BoardCaption(text: state.caption)
                    LiveActivityLockView(display: state.display)
                        .frame(width: Self.activityWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(BoardWallpaper())
        .environment(\.locale, Locale(identifier: "fr_FR"))
    }
}

/// Planche de la Dynamic Island (spec §6.2) : pour chaque état, la compacte (de part et d'autre de la caméra), la
/// minimale et la déployée, sur fond noir comme l'île. Disposition approchée : sur l'iPhone, c'est iOS qui place les
/// régions.
struct DynamicIslandBoard: View {
    let states: [LiveBoardState]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, state in
                VStack(alignment: .leading, spacing: 8) {
                    BoardCaption(text: state.caption)
                    HStack(spacing: 12) {
                        compact(state.display)
                        minimal(state.display)
                    }
                    expanded(state.display)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: WidgetSize.screen.width, height: WidgetSize.screen.height, alignment: .topLeading)
        .background(BoardWallpaper())
        .environment(\.locale, Locale(identifier: "fr_FR"))
    }

    /// Compacte : un côté de chaque côté de la caméra (le vide au milieu).
    private func compact(_ display: LiveActivityDisplay) -> some View {
        HStack(spacing: 0) {
            IslandCompactView(display: display, side: 0)
            Spacer(minLength: 0)
            IslandCompactView(display: display, side: 1)
        }
        .padding(.horizontal, 10)
        .frame(width: 236, height: 36)
        .background(Color.black, in: Capsule())
    }

    private func minimal(_ display: LiveActivityDisplay) -> some View {
        IslandMinimalView(display: display)
            .frame(width: 36, height: 36)
            .background(Color.black, in: Circle())
    }

    /// Déployée : équipes à gauche et à droite, score et game au centre, stats (ou message) en bas.
    private func expanded(_ display: LiveActivityDisplay) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                IslandTeamView(side: display.teams.first)
                    .frame(width: 64)
                Spacer(minLength: 4)
                IslandCenterView(display: display)
                Spacer(minLength: 4)
                IslandTeamView(side: display.teams.count > 1 ? display.teams[1] : nil)
                    .frame(width: 64)
            }
            IslandBottomView(display: display)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 370)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 42, style: .continuous))
    }
}
