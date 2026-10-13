import AppIntents
import LoLKit
import WidgetKit

/// Réglage du petit widget (spec §7) : l'équipe suivie dont il montre le prochain match. Sans choix, la première
/// équipe suivie. Propriétés statiques calculées (forme du modèle de widget de Xcode) : rien de mutable partagé.
struct SelectTeamIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Équipe" }
    static var description: IntentDescription { "Le prochain match de l'équipe choisie." }

    @Parameter(title: "Équipe")
    var team: TeamEntity?
}

/// Une équipe suivie, proposée dans les réglages du petit widget (lue dans follows.json, en lecture seule).
struct TeamEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Équipe" }
    static var defaultQuery: TeamQuery { TeamQuery() }

    let id: String
    let code: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(code)")
    }

    /// Équipes suivies, dans l'ordre de suivi.
    static func followed() -> [TeamEntity] {
        let follows = FileStore(directory: AppGroup.directory, readOnly: true).load(FollowList.self, from: .follows)
            ?? FollowList()
        return follows.teams.map { TeamEntity(id: $0.id, code: $0.code, name: $0.name) }
    }
}

/// Les équipes proposées : celles que l'appli suit ; par défaut, la première.
struct TeamQuery: EntityQuery {
    func entities(for identifiers: [TeamEntity.ID]) async throws -> [TeamEntity] {
        TeamEntity.followed().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [TeamEntity] {
        TeamEntity.followed()
    }

    func defaultResult() async -> TeamEntity? {
        TeamEntity.followed().first
    }
}
