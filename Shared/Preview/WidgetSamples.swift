import Foundation
import LoLKit

/// Contenus d'exemple des widgets (galerie quand aucune équipe n'est suivie, aperçus PNG), tirés de `SampleData`.
enum WidgetSamples {
    /// 15 oct., 17:05 UTC : KC en direct (1 – 0, game 2), T1 en direct masqué, GEN et KC à venir les jours suivants
    /// (quatre lignes pour le moyen widget).
    static let now = SampleData.date("2026-10-15T17:05:00Z")

    static var input: WidgetInput {
        WidgetInput(follows: SampleData.follows, settings: AppSettings(),
                    schedule: Cached(value: SchedulePage(leagueIds: [], events: SampleData.schedule + [SampleData.kcNext]),
                                     fetchedAt: now),
                    live: Cached(value: SampleData.live, fetchedAt: now))
    }

    static var live: WidgetContent {
        WidgetTimeline.content(at: now, input: input)
    }

    /// Seule T1 (anti-spoiler) est suivie : son match en direct ne montre que « En direct ».
    static var maskedLive: WidgetContent {
        var masked = input
        masked.follows = FollowList(teams: SampleData.follows.teams.filter(\.spoilerFree))
        return WidgetTimeline.content(at: now, input: masked)
    }

    /// Le lendemain à 7 h (Paris) : plus rien n'est sûr d'être en direct ; GEN vs FUR à 11 h, KC le surlendemain,
    /// T1 « Prochain · masqué ».
    static var upcoming: WidgetContent {
        WidgetTimeline.content(at: upcomingDate, input: input)
    }

    private static let upcomingDate = SampleData.date("2026-10-16T05:00:00Z")

    /// Seule T1 (anti-spoiler) est suivie, le lendemain : rien à annoncer, « Prochain · masqué ».
    static var hidden: WidgetContent {
        var masked = input
        masked.follows = FollowList(teams: SampleData.follows.teams.filter(\.spoilerFree))
        return WidgetTimeline.content(at: upcomingDate, input: masked)
    }

    /// Aucune équipe suivie.
    static var empty: WidgetContent {
        WidgetTimeline.content(at: now, input: WidgetInput())
    }
}
