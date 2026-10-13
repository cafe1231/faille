import Foundation
import LoLKit

extension WidgetInput {
    /// Les fichiers de l'appli (spec §4.4) : un fichier absent ou illisible donne une valeur vide. Avec un `FileStore`
    /// en lecture seule, rien n'est écrit ni mis de côté.
    static func load(from files: FileStore) -> WidgetInput {
        WidgetInput(
            follows: files.load(FollowList.self, from: .follows) ?? FollowList(),
            settings: files.load(AppSettings.self, from: .settings) ?? AppSettings(),
            schedule: files.load(Cached<SchedulePage>.self, from: .schedule),
            live: files.load(Cached<[MatchEvent]>.self, from: .live)
        )
    }

    /// Ce que lit l'extension : le dossier de Faille dans le groupe d'apps résolu à l'exécution, en lecture seule. Sans
    /// groupe d'apps (`AppGroup.identifier == nil`), rien ne peut être lu : les widgets le disent (`appGroupMissing`).
    static func shared() -> WidgetInput {
        var input = load(from: FileStore(directory: AppGroup.directory, readOnly: true))
        input.appGroupMissing = AppGroup.identifier == nil
        return input
    }
}
