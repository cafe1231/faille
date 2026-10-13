import AppIntents
import LoLKit
import WidgetKit

/// Entrée des widgets non configurables : ce qu'ils montrent à sa date.
struct FailleEntry: TimelineEntry {
    let date: Date
    let content: WidgetContent
}

/// Entrée du petit widget : la même chose, plus l'équipe choisie dans ses réglages (nil = la première suivie).
struct TeamEntry: TimelineEntry {
    let date: Date
    let content: WidgetContent
    let teamId: String?
}

/// Planning commun (spec §7) : une entrée à chaque date de `WidgetTimeline.entryDates` (début de chaque match, paliers
/// du compte à rebours, fin de confiance du direct et du calendrier), rechargement à `WidgetTimeline.reloadDate`
/// (5 h plus tard : les entrées couvrent 6 h, et l'appli recharge les widgets à chaque écriture). Lecture seule du
/// groupe d'apps.
enum FailleTimeline {
    static func make<Entry: TimelineEntry>(now: Date = Date(), input: WidgetInput = .shared(),
                                           _ entry: (Date, WidgetContent) -> Entry) -> Timeline<Entry> {
        let entries = WidgetTimeline.entryDates(now: now, input: input).map { date in
            entry(date, WidgetTimeline.content(at: date, input: input))
        }
        return Timeline(entries: entries, policy: .after(WidgetTimeline.reloadDate(now: now)))
    }

    /// Instantané (galerie, réglages du widget) : l'état présent ; un exemple si aucune équipe n'est encore suivie.
    static func current(isPreview: Bool, now: Date = Date()) -> WidgetContent {
        let input = WidgetInput.shared()
        if isPreview && input.follows.teams.isEmpty {
            return WidgetSamples.live
        }
        return WidgetTimeline.content(at: now, input: input)
    }
}

/// Planning des widgets de l'écran verrouillé et du moyen widget.
struct FailleProvider: TimelineProvider {
    func placeholder(in context: Context) -> FailleEntry {
        FailleEntry(date: Date(), content: WidgetSamples.live)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (FailleEntry) -> Void) {
        completion(FailleEntry(date: Date(), content: FailleTimeline.current(isPreview: context.isPreview)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<FailleEntry>) -> Void) {
        completion(FailleTimeline.make { FailleEntry(date: $0, content: $1) })
    }
}

/// Planning du petit widget : celui des autres widgets, avec l'équipe choisie dans ses réglages.
struct TeamProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TeamEntry {
        TeamEntry(date: Date(), content: WidgetSamples.live, teamId: nil)
    }

    func snapshot(for configuration: SelectTeamIntent, in context: Context) async -> TeamEntry {
        TeamEntry(date: Date(), content: FailleTimeline.current(isPreview: context.isPreview),
                  teamId: configuration.team?.id)
    }

    func timeline(for configuration: SelectTeamIntent, in context: Context) async -> Timeline<TeamEntry> {
        let teamId = configuration.team?.id
        return FailleTimeline.make { TeamEntry(date: $0, content: $1, teamId: teamId) }
    }
}
