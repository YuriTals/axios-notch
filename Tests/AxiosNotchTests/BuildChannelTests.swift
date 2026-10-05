import XCTest
@testable import AxiosNotch

final class BuildChannelTests: XCTestCase {
    func testInternalIdentificationRequiresExplicitMetadata() {
        XCTAssertFalse(BuildChannel.isTest(info: [:]))
        XCTAssertFalse(BuildChannel.isTest(info: ["AxiosBuildChannel": "production"]))
        XCTAssertTrue(BuildChannel.isTest(info: ["AxiosBuildChannel": "test"]))
    }
}

@MainActor
final class InternalBuildUpdateTests: XCTestCase {
    func testInternalBuildDoesNotFetchOrInstallProductionUpdates() async {
        let suite = "axios-internal-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var requests = 0
        let store = UpdateStore(defaults: defaults, currentVersion: "1.0.2", fetch: {
            requests += 1
            return Data()
        }, internalBuild: true)
        store.checkIfDue()
        await store.check()
        await store.install()
        XCTAssertEqual(requests, 0)
        XCTAssertFalse(store.canInstall)
        XCTAssertEqual(store.state, .idle)
    }
}
