/// Réglage « Live Activity » (spec §5.4).
public enum LiveActivityMode: String, Codable, Sendable {
    case automatic, manual
}

/// Décide quels matchs en direct ont une Live Activity (spec §6.4).
public enum LiveActivityPlanner {
    public static let maxConcurrent = 3

    /// Ids de matchs par priorité : épinglés (s'ils sont en direct), puis en automatique les matchs
    /// des équipes suivies, dans l'ordre de suivi, sauf ceux retirés à la main. Au plus `maxConcurrent`.
    public static func plan(
        live: [MatchEvent],
        follows: FollowList,
        mode: LiveActivityMode,
        pinned: [String],
        dismissed: Set<String>
    ) -> [String] {
        let liveIds = Set(live.map(\.id))
        var result = pinned.filter { liveIds.contains($0) }
        if mode == .automatic {
            let ranked = live.enumerated()
                .compactMap { position, event -> (rank: Int, position: Int, id: String)? in
                    let ranks = follows.teams.indices.filter { index in
                        event.match.teams.contains { $0.isSame(as: follows.teams[index]) }
                    }
                    return ranks.min().map { (rank: $0, position: position, id: event.id) }
                }
                .sorted { ($0.rank, $0.position) < ($1.rank, $1.position) }
            for candidate in ranked where !dismissed.contains(candidate.id) && !result.contains(candidate.id) {
                result.append(candidate.id)
            }
        }
        return Array(result.prefix(maxConcurrent))
    }
}
