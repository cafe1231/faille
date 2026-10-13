import Foundation
import LoLKit

/// `lolkit` : interroge la vraie API lolesports depuis le terminal (Windows via Docker).
@main
struct LoLKitCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let client = LoLClient()
        do {
            switch arguments.first {
            case "leagues":
                try await leagues(client)
            case "live":
                try await live(client)
            case "schedule" where arguments.count > 1:
                try await schedule(client, code: arguments[1])
            default:
                printUsage()
            }
        } catch {
            print("Erreur : \(error)")
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        Usage :
          lolkit leagues            liste des ligues
          lolkit live               matchs en direct et leurs stats
          lolkit schedule <CODE>    dernier et prochain match d'une équipe (ex. KC)
        """)
    }

    static func leagues(_ client: LoLClient) async throws {
        for league in try await client.leagues() {
            print(league.slug.padding(toLength: 28, withPad: " ", startingAt: 0) + league.name)
        }
    }

    static func live(_ client: LoLClient) async throws {
        let events = try await client.live()
        if events.isEmpty {
            print("Aucun match en direct.")
            return
        }
        for event in events {
            let teams = event.match.teams
            print("\n\(event.league.name) · Bo\(event.bestOf) · \(teams.map(\.code).joined(separator: " vs ")) · \(teams.map { String($0.gameWins) }.joined(separator: "-"))")
            if event.statsDisabled {
                print("  Stats live non fournies par Riot pour ce match.")
                continue
            }
            guard let game = event.match.games?.first(where: { $0.state == .inProgress }) else {
                print("  Entre deux games.")
                continue
            }
            do {
                let window = try await client.window(gameId: game.id, startingTime: LiveStatsTime.startingTime(now: Date()))
                guard let snapshot = window.latestSnapshot() else {
                    print("  Pas encore de frames.")
                    continue
                }
                print("  Game \(game.number) · \(snapshot.phase.rawValue) · frame \(LoLDate.format(snapshot.timestamp))")
                for team in teams {
                    if let id = team.id, let stats = snapshot.stats(for: id) {
                        print("  " + team.code.padding(toLength: 6, withPad: " ", startingAt: 0) + describe(stats))
                    }
                }
            } catch LoLAPIError.statsDisabled {
                print("  Stats désactivées (404).")
            } catch LoLAPIError.noData {
                print("  Flux vide pour l'instant.")
            }
        }
    }

    static func schedule(_ client: LoLClient, code: String) async throws {
        let catalog = try await client.teams()
        guard let team = catalog.first(where: { $0.isActive && $0.code.lowercased() == code.lowercased() }) else {
            print("Équipe \(code) introuvable.")
            return
        }
        var follows = FollowList()
        follows.follow(team)
        let leagueIds = ScheduleQuery.leagueIds(follows: follows, leagues: try await client.leagues())
        let events = try await client.schedule(leagueIds: leagueIds)
        let card = TeamCards.build(follows: follows, schedule: events, live: try await client.live()).first
        print("\(team.name) (\(team.homeLeague?.name ?? "sans ligue d'attache"))")
        if let live = card?.live {
            print("  En direct : \(live.match.teams.map(\.code).joined(separator: " vs "))")
        }
        if let last = card?.last {
            print("  Dernier   : \(last.match.teams.map { "\($0.code) \($0.gameWins)" }.joined(separator: " - ")) · \(Format.matchDate(last.startTime))")
        }
        if let next = card?.next {
            print("  Prochain  : \(next.match.teams.map(\.code).joined(separator: " vs ")) · \(Format.matchDate(next.startTime))")
        }
        if card?.live == nil && card?.last == nil && card?.next == nil {
            print("  Aucun match dans le calendrier récent.")
        }
    }

    static func describe(_ stats: TeamStats) -> String {
        "\(stats.kills) kills · \(Format.gold(stats.gold)) gold · \(stats.towers) tours · \(stats.inhibitors) inhibs · \(stats.barons) barons · drakes [\(stats.dragons.joined(separator: ", "))]"
    }
}
