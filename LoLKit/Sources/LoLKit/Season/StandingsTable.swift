import Foundation

/// Classements et tableaux prêts à afficher (spec saison §3.5), depuis `getStandings`. Des valeurs, jamais du texte :
/// l'appli formule (« 2-1 », « Quarts de finale »…).
public enum StandingsTable {
    /// Une ligne de classement (`rankings`) ; ex aequo : même `ordinal`.
    public struct Row: Sendable, Equatable {
        public let ordinal: Int
        public let team: RankedTeam

        public init(ordinal: Int, team: RankedTeam) {
            self.ordinal = ordinal
            self.team = team
        }

        public var wins: Int { team.wins }
        public var losses: Int { team.losses }
    }

    /// Bilan d'une équipe dans un système suisse.
    public struct TeamRecord: Sendable, Equatable {
        /// L'équipe (id, nom, code, logo ; sans résultat).
        public let team: MatchTeam
        public let wins: Int
        public let losses: Int

        public init(team: MatchTeam, wins: Int, losses: Int) {
            self.team = team
            self.wins = wins
            self.losses = losses
        }
    }

    /// Équipes de même bilan dans un système suisse.
    public struct RecordGroup: Sendable, Equatable {
        public let wins: Int
        public let losses: Int
        /// Par code d'équipe.
        public let teams: [MatchTeam]

        public init(wins: Int, losses: Int, teams: [MatchTeam]) {
            self.wins = wins
            self.losses = losses
            self.teams = teams
        }

        /// « 2-1 »
        public var record: String { "\(wins)-\(losses)" }
    }

    /// Un tour d'une phase finale.
    public struct Round: Sendable, Equatable {
        public enum Kind: Sendable, Equatable {
            case quarterFinal
            case semiFinal
            case final
        }

        public let kind: Kind
        public let matches: [BracketMatch]

        public init(kind: Kind, matches: [BracketMatch]) {
            self.kind = kind
            self.matches = matches
        }
    }

    public enum Content: Sendable, Equatable {
        /// Classement (`rankings` non vide).
        case table([Row])
        /// Système suisse : bilans recalculés depuis `outcome` des matchs `completed`, meilleurs bilans d'abord.
        case swiss([RecordGroup])
        /// Phase finale à 7 matchs (Mondial) : [0-3] quarts, [4] = vainqueurs de [0] et [1], [5] = de [2] et [3],
        /// [6] finale (ordre vérifié sur 2025).
        case bracket([Round])
        /// Autre tableau (play-offs d'une ligue, play-ins) : les matchs dans l'ordre de l'API.
        case matches([BracketMatch])
    }

    public struct Stage: Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let slug: String
        public let content: Content

        public init(id: String, name: String, slug: String, content: Content) {
            self.id = id
            self.name = name
            self.slug = slug
            self.content = content
        }
    }

    /// Une entrée par étape, dans l'ordre de l'API. Choix : `rankings` → `.table` ; slug `swiss` → `.swiss` ; slug
    /// `knockouts` à 7 matchs → `.bracket` ; sinon `.matches`. Une étape sans aucun match ni classement est omise.
    public static func build(standings: Standings) -> [Stage] {
        standings.stages.compactMap { stage in
            let rankings = stage.sections.flatMap(\.rankings)
            let matches = stage.sections.flatMap(\.matches)
            let content: Content
            if !rankings.isEmpty {
                content = .table(rankings.sorted { $0.ordinal < $1.ordinal }
                    .flatMap { ranking in ranking.teams.map { Row(ordinal: ranking.ordinal, team: $0) } })
            } else if matches.isEmpty {
                return nil
            } else if stage.slug == "swiss" {
                content = .swiss(swissGroups(matches))
            } else if stage.slug == "knockouts", matches.count == 7 {
                content = .bracket([Round(kind: .quarterFinal, matches: Array(matches[0..<4])),
                                    Round(kind: .semiFinal, matches: Array(matches[4..<6])),
                                    Round(kind: .final, matches: [matches[6]])])
            } else {
                content = .matches(matches)
            }
            return Stage(id: stage.id, name: stage.name, slug: stage.slug, content: content)
        }
    }

    /// Bilans d'un système suisse : victoires et défaites de chaque équipe connue (hors « TBD ») sur les matchs
    /// `completed` (`outcome` win / loss) ; une équipe sans match joué est à 0-0.
    public static func swissRecords(_ matches: [BracketMatch]) -> [TeamRecord] {
        var order: [String] = []
        var records: [String: (team: MatchTeam, wins: Int, losses: Int)] = [:]
        for match in matches {
            for team in match.teams where !team.isPlaceholder {
                let key = team.id ?? team.code
                if records[key] == nil {
                    order.append(key)
                    records[key] = (MatchTeam(id: team.id, name: team.name, code: team.code, image: team.image,
                                              result: nil), 0, 0)
                }
                guard match.state == .completed else { continue }
                switch team.result?.outcome {
                case "win": records[key]?.wins += 1
                case "loss": records[key]?.losses += 1
                default: break
                }
            }
        }
        return order.compactMap { records[$0] }.map { TeamRecord(team: $0.team, wins: $0.wins, losses: $0.losses) }
    }

    static func swissGroups(_ matches: [BracketMatch]) -> [RecordGroup] {
        let grouped = Dictionary(grouping: swissRecords(matches)) { "\($0.wins)-\($0.losses)" }
        return grouped.values.map { entries in
            RecordGroup(wins: entries[0].wins, losses: entries[0].losses,
                        teams: entries.map(\.team).sorted { $0.code < $1.code })
        }.sorted { $0.wins != $1.wins ? $0.wins > $1.wins : $0.losses < $1.losses }
    }
}
