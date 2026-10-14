/// Nom d'un joueur tel que le flux l'écrit (« KC Canna ») → nom affiché (« Canna »), spec saison §1.5.
public enum PlayerName {
    /// Retire le préfixe « CODE » s'il est exactement le code d'équipe suivi d'une espace ; sinon le nom tel quel
    /// (un pseudo à espace comme « Hans Sama » n'est jamais coupé ailleurs). Préférer `TeamPlayer.summonerName` du
    /// catalogue quand il est connu.
    public static func display(_ summonerName: String, teamCode: String?) -> String {
        guard let teamCode, !teamCode.isEmpty, summonerName.hasPrefix(teamCode + " ") else { return summonerName }
        let rest = summonerName.dropFirst(teamCode.count + 1)
        return rest.isEmpty ? summonerName : String(rest)
    }
}
