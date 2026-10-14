import Foundation

/// Un événement du fil de la game (spec fonctionnalités §4), déduit de deux frames successives.
public struct TimelineEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case kills
        /// Drake tué, avec son type (`infernal`, `ocean`, `cloud`, `mountain`, `hextech`, `chemtech`, `elder`).
        case dragon(String)
        case baron
        case tower
        case inhibitor
    }

    /// Temps de jeu de la frame où l'événement apparaît, en secondes depuis la première frame (même règle que le chrono :
    /// pauses comprises). L'événement a eu lieu entre la frame précédente et celle-ci.
    public let gameTime: TimeInterval
    /// Équipe qui a marqué (id lolesports).
    public let teamId: String
    public let kind: Kind
    /// Nombre gagné entre les deux frames (« +2 kills ») ; 1 pour un drake (un événement par drake).
    public let count: Int
    /// Pour les kills : pseudos des joueurs dont les kills ont augmenté, dans l'ordre du flux, seulement si la somme de
    /// leurs hausses vaut exactement `count` ; sinon vide (« +2 kills » sans nom : pas d'attribution inventée). C'est une
    /// liste de joueurs, pas un nom par kill : un joueur à plusieurs kills n'y figure qu'une fois (« +4 kills » peut porter
    /// 3 noms) ; l'appli affiche les noms en liste.
    public let players: [String]

    public init(gameTime: TimeInterval, teamId: String, kind: Kind, count: Int, players: [String] = []) {
        self.gameTime = gameTime
        self.teamId = teamId
        self.kind = kind
        self.count = count
        self.players = players
    }
}

/// Fil des événements d'une game : différences entre frames successives (spec fonctionnalités §4). La première frame sert
/// de référence (rien n'est inventé avant elle). Pas de hérauts ni de larves : le flux `window` ne les donne pas.
/// Anti-spoiler : le fil raconte la game (kills, objectifs) ; l'appli n'appelle pas cette fonction (et ne demande aucune
/// frame) pour un match masqué.
public enum GameTimeline {
    /// Événements dans l'ordre chronologique (l'appli les affiche du plus récent au plus ancien). Pour chaque pas : équipe
    /// bleue puis rouge ; kills, drakes, barons, tours, inhibiteurs. Une baisse (frame incohérente) n'est jamais un
    /// événement.
    /// - Parameters:
    ///   - snapshots: frames d'une même game (direct : une par lecture de 10 s ; relecture : une par pas de 60 s), triées
    ///     ici par horodatage (deux frames au même instant gardent leur ordre de remise).
    ///   - firstFrameTime: première frame de la game (fenêtre lue sans `startingTime`) : le 0:00 du temps de jeu.
    public static func events(from snapshots: [GameSnapshot], firstFrameTime: Date) -> [TimelineEvent] {
        let ordered = chronological(snapshots)
        guard ordered.count > 1 else { return [] }
        var events: [TimelineEvent] = []
        for (previous, current) in zip(ordered, ordered.dropFirst()) {
            let gameTime = max(0, current.timestamp.timeIntervalSince(firstFrameTime))
            events += changes(team: current.blueTeamId, before: previous.blue, after: current.blue,
                              playersBefore: previous.bluePlayers, playersAfter: current.bluePlayers, at: gameTime)
            events += changes(team: current.redTeamId, before: previous.red, after: current.red,
                              playersBefore: previous.redPlayers, playersAfter: current.redPlayers, at: gameTime)
        }
        return events
    }

    /// Frames par horodatage croissant ; à horodatage égal, l'ordre de remise départage (tri stable explicite : `sorted(by:)`
    /// ne promet pas la stabilité). Partagé avec `GoldSeries`, qui suit les mêmes frames.
    static func chronological(_ snapshots: [GameSnapshot]) -> [GameSnapshot] {
        snapshots.enumerated()
            .sorted { ($0.element.timestamp, $0.offset) < ($1.element.timestamp, $1.offset) }
            .map(\.element)
    }

    static func changes(team: String, before: TeamStats, after: TeamStats, playersBefore: [PlayerLine],
                        playersAfter: [PlayerLine], at gameTime: TimeInterval) -> [TimelineEvent] {
        var events: [TimelineEvent] = []
        let kills = after.kills - before.kills
        if kills > 0 {
            events.append(TimelineEvent(gameTime: gameTime, teamId: team, kind: .kills, count: kills,
                                        players: killers(before: playersBefore, after: playersAfter, teamKills: kills)))
        }
        if after.dragons.count > before.dragons.count {
            for type in after.dragons.dropFirst(before.dragons.count) {
                events.append(TimelineEvent(gameTime: gameTime, teamId: team, kind: .dragon(type), count: 1))
            }
        }
        let counted: [(TimelineEvent.Kind, Int)] = [
            (.baron, after.barons - before.barons),
            (.tower, after.towers - before.towers),
            (.inhibitor, after.inhibitors - before.inhibitors),
        ]
        for (kind, gained) in counted where gained > 0 {
            events.append(TimelineEvent(gameTime: gameTime, teamId: team, kind: kind, count: gained))
        }
        return events
    }

    /// Joueurs dont les kills ont augmenté, si la somme de leurs hausses explique exactement les kills de l'équipe. Les
    /// joueurs se suivent par position (le flux les donne toujours dans l'ordre de `participantId`) ; un pseudo absent ou
    /// différent d'une frame à l'autre : pas d'attribution.
    static func killers(before: [PlayerLine], after: [PlayerLine], teamKills: Int) -> [String] {
        guard before.count == after.count else { return [] }
        var names: [String] = []
        var total = 0
        for (previous, player) in zip(before, after) where player.kills > previous.kills {
            guard !player.name.isEmpty, player.name == previous.name else { return [] }
            names.append(player.name)
            total += player.kills - previous.kills
        }
        return total == teamKills ? names : []
    }
}
