import Foundation
import Testing
@testable import LoLKit

@Suite struct StorageTests {
    @Test func candidatesKeepSpecOrderWithoutDuplicates() {
        let list = AppGroupResolver.candidates(
            provisioned: ["group.com.cafe1231.faille.TA6JYZWPU9"],
            altAppGroups: ["group.com.cafe1231.faille.TA6JYZWPU9", "group.com.cafe1231.faille.ALT", ""],
            configured: "group.com.cafe1231.faille"
        )
        #expect(list == ["group.com.cafe1231.faille.TA6JYZWPU9", "group.com.cafe1231.faille.ALT", "group.com.cafe1231.faille"])
        #expect(AppGroupResolver.candidates(provisioned: [], altAppGroups: [], configured: "group.x") == ["group.x"])
    }

    @Test func firstAvailableWins() {
        let list = ["a", "b", "c"]
        #expect(AppGroupResolver.first(of: list) { $0 != "a" } == "b")
        #expect(AppGroupResolver.first(of: list) { _ in false } == nil)
    }

    @Test func settingsHaveDefaultsAndRoundTrip() throws {
        let defaults = AppSettings()
        #expect(defaults.liveActivityMode == .automatic)
        #expect(defaults.revealedMatchIds.isEmpty)
        let custom = AppSettings(liveActivityMode: .manual, revealedMatchIds: ["m1", "m2"])
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(custom)) == custom)
    }

    @Test func settingsDecodeTolerantly() throws {
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)) == AppSettings())
        let future = #"{"liveActivityMode":"turbo","revealedMatchIds":["m1"],"pinned":["m2"]}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(future.utf8))
        #expect(decoded.liveActivityMode == .automatic)
        #expect(decoded.revealedMatchIds == ["m1"])
    }
}
