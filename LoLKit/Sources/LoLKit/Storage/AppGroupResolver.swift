/// Choix du groupe d'apps (spec §4.4). Les outils de signature le renomment (AltServer :
/// `group.com.cafe1231.faille.<TEAMID>`) : on ne l'écrit jamais en dur, on essaie des candidats.
public enum AppGroupResolver {
    /// Candidats dans l'ordre de la spec : groupes du profil embarqué, puis clé `ALTAppGroups` de l'Info.plist,
    /// puis le nom configuré. Sans doublon ni chaîne vide.
    public static func candidates(provisioned: [String], altAppGroups: [String], configured: String) -> [String] {
        var seen: Set<String> = []
        return (provisioned + altAppGroups + [configured]).filter { group in
            !group.isEmpty && seen.insert(group).inserted
        }
    }

    /// Premier candidat dont le conteneur existe (côté iOS : `containerURL` non nil), sinon nil.
    public static func first(of candidates: [String], isAvailable: (String) -> Bool) -> String? {
        candidates.first(where: isAvailable)
    }
}
