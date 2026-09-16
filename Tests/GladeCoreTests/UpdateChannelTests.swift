import XCTest
@testable import GladeCore

final class UpdateChannelTests: XCTestCase {
    func testChannelSubscriptionsCascadeTowardStable() {
        XCTAssertEqual(UpdateChannel.release.sparkleAllowedChannels, [])
        XCTAssertEqual(UpdateChannel.beta.sparkleAllowedChannels, ["beta"])
        XCTAssertEqual(UpdateChannel.alpha.sparkleAllowedChannels, ["beta", "alpha"])
    }

    func testUnknownPreferenceDefaultsToReleaseAndChangesAreReadLive() throws {
        let suite = "GladeUpdateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(UpdateChannel.current(in: defaults), .release)
        defaults.set("unrecognized-channel", forKey: UpdateChannel.storageKey)
        XCTAssertEqual(UpdateChannel.current(in: defaults), .release)
        defaults.set("alpha", forKey: UpdateChannel.storageKey)
        XCTAssertEqual(UpdateChannel.current(in: defaults), .alpha)
        defaults.set("beta", forKey: UpdateChannel.storageKey)
        XCTAssertEqual(UpdateChannel.current(in: defaults), .beta)
    }

    func testStableSelectionWarnsWhenInstalledBuildIsPrerelease() {
        XCTAssertEqual(UpdateChannel.installed(in: "1.5.0-beta.2"), .beta)
        XCTAssertEqual(UpdateChannel.installed(in: "1.5.0-alpha.1"), .alpha)
        XCTAssertEqual(UpdateChannel.installed(in: "1.5.0"), .release)
        XCTAssertTrue(UpdateChannel.release.requiresNewerBuild(than: .beta))
        XCTAssertTrue(UpdateChannel.beta.requiresNewerBuild(than: .alpha))
        XCTAssertFalse(UpdateChannel.alpha.requiresNewerBuild(than: .release))
        XCTAssertFalse(UpdateChannel.release.requiresNewerBuild(than: .release))
    }
}
