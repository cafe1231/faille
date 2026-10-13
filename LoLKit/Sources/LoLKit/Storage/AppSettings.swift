/// Réglages de l'appli, enregistrés dans le groupe d'apps (lus aussi par les widgets et la Live Activity aux étapes 3-4).
public struct AppSettings: Codable, Sendable, Equatable {
    /// Réglage « Live Activity » (spec §5.4), utilisé à l'étape 4.
    public var liveActivityMode: LiveActivityMode
    /// Matchs que l'utilisateur a choisi de révéler malgré l'anti-spoiler (spec §8).
    public var revealedMatchIds: Set<String>

    public init(liveActivityMode: LiveActivityMode = .automatic, revealedMatchIds: Set<String> = []) {
        self.liveActivityMode = liveActivityMode
        self.revealedMatchIds = revealedMatchIds
    }

    private enum CodingKeys: String, CodingKey {
        case liveActivityMode, revealedMatchIds
    }

    /// Décodage tolérant : champ absent ou valeur inconnue (version plus récente) → valeur par défaut.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        liveActivityMode = (try? container.decodeIfPresent(LiveActivityMode.self, forKey: .liveActivityMode)) ?? .automatic
        revealedMatchIds = (try? container.decodeIfPresent(Set<String>.self, forKey: .revealedMatchIds)) ?? []
    }
}
