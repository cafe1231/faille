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

/// Squelette du panneau des joueurs d'une game : sélecteur d'équipe, en-tête et cinq lignes « rôle · champion · KDA · CS »,
/// à peu près à la hauteur de `PlayersPanel`.
struct PlayersSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBlock(height: 32, radius: 8)
            HStack {
                SkeletonBlock(width: 60, height: 9)
                Spacer()
                SkeletonBlock(width: 24, height: 9)
            }
            .frame(height: 14)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<5, id: \.self) { _ in
                    HStack {
                        SkeletonBlock(width: 28, height: 11)
                        SkeletonBlock(width: 90, height: 11)
                        Spacer()
                        SkeletonBlock(width: 52, height: 11)
                        SkeletonBlock(width: 28, height: 11)
                    }
                    .frame(height: 16)
                }
            }
        }
        .glassCard(radius: Radius.inner, padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Joueurs en chargement")
    }
}

/// Squelette de la zone des stats d'une game : le panneau d'équipe, puis celui des joueurs. Il a la hauteur des deux vrais
/// panneaux : quand ils arrivent, le bouton « Épingler » en dessous ne saute pas.
struct GameStatsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatsSkeleton()
            PlayersSkeleton()
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
