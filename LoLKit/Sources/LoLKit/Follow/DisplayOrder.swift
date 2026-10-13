extension FollowList {
    /// Ordre d'affichage des deux équipes d'un match, en index de `teams` : `preferred` (l'équipe d'une carte)
    /// à gauche s'il joue, sinon l'équipe suivie depuis le plus longtemps, sinon l'ordre de l'API.
    public func displayOrder(_ teams: [MatchTeam], preferring preferred: FollowedTeam? = nil) -> [Int] {
        guard teams.count == 2 else { return Array(teams.indices) }
        if let preferred {
            if teams[0].isSame(as: preferred) { return [0, 1] }
            if teams[1].isSame(as: preferred) { return [1, 0] }
        }
        let ranks = teams.map { team in self.teams.firstIndex { team.isSame(as: $0) } }
        switch (ranks[0], ranks[1]) {
        case (nil, .some):
            return [1, 0]
        case let (left?, right?) where right < left:
            return [1, 0]
        default:
            return [0, 1]
        }
    }
}
