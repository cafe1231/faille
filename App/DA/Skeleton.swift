import SwiftUI

/// Chargement (spec finitions §10) : une forme arrondie au gabarit du contenu attendu, balayée lentement par un reflet ;
/// figée sous « Réduire les animations ». Remplace les `ProgressView` et les textes d'attente (Détail, catalogue).
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var radius: CGFloat = 6
    @ReduceMotion var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(Palette.fill(.placeholder))
            .overlay {
                if Motion.runs(.shimmer, reduceMotion: reduceMotion) {
                    Shimmer().clipShape(shape)
                }
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

/// Avancement du reflet (0 … 1) à une date : calculé à partir de l'heure, donc le même pour tous les squelettes de
/// l'écran, qui balaient ensemble.
@MainActor
enum ShimmerClock {
    static func progress(at date: Date) -> Double {
        let period = Motion.Duration.shimmer
        return date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    }
}

private struct ShimmerProgressKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    /// Avancement du reflet fourni par le `ShimmerScope` englobant ; nil hors d'un conteneur de squelettes.
    var shimmerProgress: Double? {
        get { self[ShimmerProgressKey.self] }
        set { self[ShimmerProgressKey.self] = newValue }
    }
}

/// Un seul minuteur pour tous les blocs d'un conteneur de squelettes (audit D.1, finitions M5) : il publie l'avancement
/// du reflet dans l'environnement, que chaque `SkeletonBlock` lit. Rafraîchi 30 fois par seconde au plus (un balayage
/// lent n'a pas besoin de 120 images par seconde). Sans effet sous « Réduire les animations » (aucun reflet) et dans un
/// `ShimmerScope` déjà présent : les conteneurs emboîtés partagent le minuteur du premier.
struct ShimmerScope<Content: View>: View {
    @Environment(\.shimmerProgress) var parent
    @ReduceMotion var reduceMotion
    @ViewBuilder var content: Content

    var body: some View {
        if parent != nil || !Motion.runs(.shimmer, reduceMotion: reduceMotion) {
            content
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                content.environment(\.shimmerProgress, ShimmerClock.progress(at: context.date))
            }
        }
    }
}

/// Reflet qui traverse un squelette de gauche à droite, une fois toutes les `Motion.Duration.shimmer` secondes. Prend son
/// avancement du `ShimmerScope` englobant ; un bloc isolé (hors conteneur) garde son propre minuteur.
private struct Shimmer: View {
    @Environment(\.shimmerProgress) private var shared

    var body: some View {
        GeometryReader { proxy in
            if let shared {
                sweep(width: proxy.size.width, progress: shared)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    sweep(width: proxy.size.width, progress: ShimmerClock.progress(at: context.date))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func sweep(width: CGFloat, progress: Double) -> some View {
        let band = max(width * 0.5, 40)
        return LinearGradient(colors: [.clear, Color.white.opacity(0.10), .clear],
                              startPoint: .leading, endPoint: .trailing)
            .frame(width: band)
            .offset(x: -band + (width + band) * progress)
    }
}

/// Squelette du panneau de stats d'une game, au gabarit de `TeamStatsPanel` (même espacement de 8 pt, lignes de 19 pt) :
/// kills, gold, barre de gold, tours, inhibiteurs, drakes avec leur ligne de types (audit B-D15), barons.
struct StatsSkeleton: View {
    /// Hauteur d'une ligne « valeur · libellé · valeur » (la ligne de texte `.stat` du vrai panneau).
    private static let rowHeight: CGFloat = 19
    /// Hauteur de la ligne des types de drakes sous la valeur (texte `.secondary`).
    private static let typesHeight: CGFloat = 16

    var body: some View {
        ShimmerScope {
            VStack(spacing: 8) {
                row()
                row()
                SkeletonBlock(height: 5, radius: 2.5)
                row()
                row()
                VStack(spacing: 1) {
                    row()
                    HStack {
                        SkeletonBlock(width: 92, height: 11)
                        Spacer()
                        SkeletonBlock(width: 48, height: 11)
                    }
                    .frame(height: Self.typesHeight)
                }
                row()
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stats en chargement")
    }

    private func row() -> some View {
        HStack {
            SkeletonBlock(width: 34, height: 14)
            Spacer()
            SkeletonBlock(width: 84, height: 11)
            Spacer()
            SkeletonBlock(width: 34, height: 14)
        }
        .frame(height: Self.rowHeight)
    }
}

/// Squelette de la draft (`DraftStrip`) : deux rangées « code · cinq champions de 40 pt ».
struct DraftSkeleton: View {
    var body: some View {
        ShimmerScope {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 8) {
                        SkeletonBlock(width: 36, height: 11)
                        ForEach(0..<5, id: \.self) { _ in
                            SkeletonBlock(width: 40, height: 40, radius: 40 * 0.22)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Draft en chargement")
    }
}

/// Squelette de la courbe de l'écart de gold (`GoldChartCard`) : l'en-tête, puis la courbe à sa hauteur.
struct GoldCurveSkeleton: View {
    var body: some View {
        ShimmerScope {
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(width: 96, height: 11)
                SkeletonBlock(height: GoldChartCard.height, radius: 12)
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Courbe de gold en chargement")
    }
}

/// Squelette du fil de la game (`TimelineCard`) : l'en-tête, puis trois lignes.
struct TimelineSkeleton: View {
    var body: some View {
        ShimmerScope {
            VStack(alignment: .leading, spacing: 10) {
                SkeletonBlock(width: 110, height: 11)
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonBlock(height: 14)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fil de la game en chargement")
    }
}

/// Squelette de la zone des stats d'une game, dans l'ordre de `MatchDetailView.gameStats` : la draft, le panneau d'équipe,
/// la courbe de gold, la section « Joueurs » enrichie (`BuildPlayersSkeleton`, spec fonctionnalités §3) et le fil. La
/// draft, le panneau d'équipe, la courbe et les joueurs ont la hauteur du vrai. Le fil, non : il grossit pendant la
/// relecture d'une game en direct révélée ou non suivie (de trois lignes de squelette à dix et « Tout le fil », environ
/// 170 pt) et le bouton « Épingler » en dessous peut descendre alors ; sa position est à juger par Dan après l'essai sur
/// l'iPhone (le remonter, ou une hauteur minimale du fil).
struct GameStatsSkeleton: View {
    var body: some View {
        // Un seul minuteur de reflet pour tout le groupe (`BuildPlayersSkeleton` aussi, par l'environnement).
        ShimmerScope {
            VStack(alignment: .leading, spacing: 14) {
                DraftSkeleton()
                StatsSkeleton()
                GoldCurveSkeleton()
                BuildPlayersSkeleton()
                TimelineSkeleton()
            }
        }
    }
}

/// Rangée de pilules en squelette : des capsules de 29 pt dans la zone tactile de 44 pt des vraies `PillButton`, pour
/// que la rangée ne change pas de hauteur au chargement.
struct PillsSkeleton: View {
    let widths: [CGFloat]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                SkeletonBlock(width: width, height: 29, radius: 14.5)
            }
        }
        .frame(height: PillButton<EmptyView>.touchHeight)
    }
}

/// Squelette du Détail avant `getEventDetails` : pilules de games, puis stats et joueurs. Les pilules ont les largeurs
/// du vrai (« G1 ✓ » 57 pt, « G2 · en direct » 122 pt, « G3 » 43 pt ; audit B-D15).
struct DetailLoadingSkeleton: View {
    var body: some View {
        ShimmerScope {
            VStack(alignment: .leading, spacing: 14) {
                PillsSkeleton(widths: [57, 122, 43])
                GameStatsSkeleton()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement du match")
    }
}

/// Squelette de lignes d'équipes (catalogue, recherche) : badge, nom, ligue, étoile — gabarit de `CatalogTeamRow`.
struct TeamRowsSkeleton: View {
    var count = 5

    var body: some View {
        ShimmerScope {
            VStack(spacing: 4) {
                ForEach(0..<count, id: \.self) { _ in
                    HStack(spacing: 10) {
                        SkeletonBlock(width: 34, height: 34, radius: 11)
                        VStack(alignment: .leading, spacing: 6) {
                            SkeletonBlock(width: 140, height: 13)
                            SkeletonBlock(width: 64, height: 10)
                        }
                        Spacer(minLength: 8)
                        SkeletonBlock(width: 20, height: 20, radius: 10)
                            .frame(width: 44, height: 44)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement des équipes")
    }
}

/// Squelette de la carte « Suivre la ligue » (`LeagueFollowRow`) : l'étoile et son libellé, puis « Suivre ses N équipes ».
/// 68 pt comme la vraie (zone de 44 pt, marge de 12 pt) ; sans elle, la liste sautait d'environ 80 pt au chargement
/// (audit B-E1).
struct LeagueFollowSkeleton: View {
    var body: some View {
        ShimmerScope {
            HStack(spacing: 10) {
                SkeletonBlock(width: 18, height: 18, radius: 9)
                SkeletonBlock(width: 96, height: 13)
                Spacer(minLength: 8)
                SkeletonBlock(width: 120, height: 12)
            }
            .frame(minHeight: 44)
        }
        .glassCard(radius: Radius.inner, padding: 12)
        .accessibilityHidden(true)
    }
}

/// Squelette de « Toutes les ligues » : pilules de ligues, carte « Suivre la ligue », puis lignes d'équipes.
struct LeagueLoadingSkeleton: View {
    var body: some View {
        ShimmerScope {
            VStack(alignment: .leading, spacing: 14) {
                PillsSkeleton(widths: [72, 56, 88, 64])
                LeagueFollowSkeleton()
                TeamRowsSkeleton()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement des ligues")
    }
}
