/// Une équipe suivie et ses réglages.
public struct FollowedTeam: Codable, Sendable, Equatable, Identifiable {
    public static let defaultColorHex = "#6FD3FF"

    public let id: String
    public var code: String
    public var name: String
    public var image: String?
    public var homeLeagueName: String?
    public var spoilerFree: Bool
    /// Couleur tirée du logo (calculée par l'appli avec `TeamColor`).
    public var autoColorHex: String?
    /// Couleur choisie à la main ; prioritaire.
    public var colorOverrideHex: String?

    public init(id: String, code: String, name: String, image: String? = nil, homeLeagueName: String? = nil,
                spoilerFree: Bool = false, autoColorHex: String? = nil, colorOverrideHex: String? = nil) {
        self.id = id
        self.code = code
        self.name = name
        self.image = image
        self.homeLeagueName = homeLeagueName
        self.spoilerFree = spoilerFree
        self.autoColorHex = autoColorHex
        self.colorOverrideHex = colorOverrideHex
    }

    private enum CodingKeys: String, CodingKey {
        case id, code, name, image, homeLeagueName, spoilerFree, autoColorHex, colorOverrideHex
    }

    /// Décodage tolérant : seuls `id`, `code` et `name` sont indispensables, le reste a une valeur par défaut, y compris
    /// un champ optionnel d'un mauvais type (une liste enregistrée par une autre version ne doit pas perdre l'équipe).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        code = try container.decode(String.self, forKey: .code)
        name = try container.decode(String.self, forKey: .name)
        image = try? container.decodeIfPresent(String.self, forKey: .image)
        homeLeagueName = try? container.decodeIfPresent(String.self, forKey: .homeLeagueName)
        spoilerFree = (try? container.decodeIfPresent(Bool.self, forKey: .spoilerFree)) ?? false
        autoColorHex = try? container.decodeIfPresent(String.self, forKey: .autoColorHex)
        colorOverrideHex = try? container.decodeIfPresent(String.self, forKey: .colorOverrideHex)
    }

    public init(team: Team) {
        id = team.id
        code = team.code
        name = team.name
        image = team.image
        homeLeagueName = team.homeLeague?.name
        spoilerFree = false
        autoColorHex = nil
        colorOverrideHex = nil
    }

    /// Couleur à utiliser partout (Vitrail : une teinte = une équipe).
    public var colorHex: String { colorOverrideHex ?? autoColorHex ?? Self.defaultColorHex }
}

extension MatchTeam {
    /// Vrai si cette équipe d'un match est l'équipe suivie : id, sinon nom, sinon logo. Jamais le code seul (spec §4.2).
    public func isSame(as team: FollowedTeam) -> Bool {
        if let id { return id == team.id }
        if name.lowercased() == team.name.lowercased() { return true }
        if let image, let other = team.image { return image == other }
        return false
    }
}

/// Les équipes suivies, dans l'ordre où elles ont été suivies.
public struct FollowList: Codable, Sendable, Equatable {
    public private(set) var teams: [FollowedTeam]

    public init(teams: [FollowedTeam] = []) {
        self.teams = teams
    }

    private enum CodingKeys: String, CodingKey {
        case teams
    }

    /// Une entrée illisible est ignorée : les autres équipes suivies sont conservées.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teams = try container.decode(LossyArray<FollowedTeam>.self, forKey: .teams).elements
    }

    public func contains(id: String) -> Bool {
        teams.contains { $0.id == id }
    }

    public func team(id: String) -> FollowedTeam? {
        teams.first { $0.id == id }
    }

    /// Équipes suivies présentes dans ce match, dans l'ordre de suivi.
    public func followed(in matchTeams: [MatchTeam]) -> [FollowedTeam] {
        teams.filter { followed in matchTeams.contains { $0.isSame(as: followed) } }
    }

    public func involves(_ matchTeams: [MatchTeam]) -> Bool {
        !followed(in: matchTeams).isEmpty
    }

    public mutating func follow(_ team: Team) {
        guard !contains(id: team.id) else { return }
        teams.append(FollowedTeam(team: team))
    }

    public mutating func unfollow(id: String) {
        teams.removeAll { $0.id == id }
    }

    public mutating func setSpoilerFree(_ on: Bool, id: String) {
        update(id) { $0.spoilerFree = on }
    }

    public mutating func setAutoColor(_ hex: String, id: String) {
        update(id) { $0.autoColorHex = hex }
    }

    public mutating func setColorOverride(_ hex: String?, id: String) {
        update(id) { $0.colorOverrideHex = hex }
    }

    /// Met à jour nom, code, logo et ligue depuis `getTeams` (renommages de sponsor).
    public mutating func refresh(from catalog: [Team]) {
        for team in catalog {
            update(team.id) {
                $0.code = team.code
                $0.name = team.name
                $0.image = team.image
                $0.homeLeagueName = team.homeLeague?.name
            }
        }
    }

    private mutating func update(_ id: String, _ change: (inout FollowedTeam) -> Void) {
        guard let index = teams.firstIndex(where: { $0.id == id }) else { return }
        change(&teams[index])
    }
}
