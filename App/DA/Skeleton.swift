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
            .fill(Color.white.opacity(0.09))
            .overlay {
                if Motion.runs(.shimmer, reduceMotion: reduceMotion) {
                    Shimmer().clipShape(shape)
                }
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }
}

/// Reflet qui traverse un squelette de gauche à droite, une fois toutes les `Motion.Duration.shimmer` secondes ; calculé
/// à partir de l'heure : tous les squelettes de l'écran balaient ensemble. Rafraîchi 30 fois par seconde au plus
/// (un balayage lent n'a pas besoin de 120 images par seconde).
private struct Shimmer: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let band = max(width * 0.5, 40)
                let period = Motion.Duration.shimmer
                let progress = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
                LinearGradient(colors: [.clear, Color.white.opacity(0.10), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: band)
                    .offset(x: -band + (width + band) * progress)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Squelette du panneau de stats d'une game : six lignes « valeur · libellé · valeur » et la barre de gold, au gabarit
/// de `TeamStatsPanel`.
struct StatsSkeleton: View {
    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<6, id: \.self) { row in
                HStack {
                    SkeletonBlock(width: 34, height: 14)
                    Spacer()
                    SkeletonBlock(width: 84, height: 11)
                    Spacer()
                    SkeletonBlock(width: 34, height: 14)
                }
                if row == 1 {
                    SkeletonBlock(height: 5, radius: 2.5)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Stats en chargement")
    }
}

/// Squelette de la draft (`DraftStrip`) : deux rangées « code · cinq champions de 40 pt ».
struct DraftSkeleton: View {
    var body: some View {
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
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Draft en chargement")
    }
}

/// Squelette de la courbe de l'écart de gold (`GoldChartCard`) : l'en-tête, puis la courbe à sa hauteur.
struct GoldCurveSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 96, height: 11)
            SkeletonBlock(height: GoldChartCard.height, radius: 12)
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Courbe de gold en chargement")
    }
}

/// Squelette du fil de la game (`TimelineCard`) : l'en-tête, puis trois lignes.
struct TimelineSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SkeletonBlock(width: 110, height: 11)
            ForEach(0..<3, id: \.self) { _ in
                SkeletonBlock(height: 14)
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
        VStack(alignment: .leading, spacing: 14) {
            DraftSkeleton()
            StatsSkeleton()
            GoldCurveSkeleton()
            BuildPlayersSkeleton()
            TimelineSkeleton()
        }
    }
}

/// Squelette du Détail avant `getEventDetails` : pilules de games, puis stats et joueurs.
struct DetailLoadingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonBlock(width: 48, height: 30, radius: 15)
                }
            }
            GameStatsSkeleton()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement du match")
    }
}

/// Squelette de lignes d'équipes (catalogue, recherche) : badge, nom, ligue, étoile — gabarit de `CatalogTeamRow`.
struct TeamRowsSkeleton: View {
    var count = 5

    var body: some View {
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
        .glassCard(radius: Radius.inner, padding: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement des équipes")
    }
}

/// Squelette de « Toutes les ligues » : pilules de ligues, puis lignes d'équipes.
struct LeagueLoadingSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ForEach([72, 56, 88, 64], id: \.self) { width in
                    SkeletonBlock(width: CGFloat(width), height: 30, radius: 15)
                }
            }
            TeamRowsSkeleton()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chargement des ligues")
    }
}
