//
//  ShieldWriterTests.swift
//  BrokeTests
//

import ManagedSettings
import XCTest
@testable import Broke

final class ShieldWriterTests: BrokeTestCase {
    private var store: RecordingShieldTarget!

    override func setUp() {
        super.setUp()
        store = RecordingShieldTarget()
    }

    func testEmptySelectionsWriteNothingToShield() {
        ShieldWriter.apply(Fixture.profile(), to: store)

        XCTAssertNil(store.shieldedApplications)
        XCTAssertEqual(store.shieldedCategories, ShieldSettings.ActivityCategoryPolicy.none)
        XCTAssertNil(store.shieldedWebDomains)
    }

    func testDenyListLeavesTheWebFilterOff() {
        ShieldWriter.apply(Fixture.profile(restrictWebToAllowlist: false), to: store)

        XCTAssertEqual(store.blockedByFilter, WebContentSettings.FilterPolicy.none)
    }

    func testAllowListWithNoAllowedSitesBlocksAllWeb() {
        ShieldWriter.apply(Fixture.profile(restrictWebToAllowlist: true), to: store)

        XCTAssertEqual(store.blockedByFilter, .all())
    }

    func testAllowListClearsThePerDomainShield() {
        store.shieldedWebDomains = []
        ShieldWriter.apply(Fixture.profile(restrictWebToAllowlist: true), to: store)

        XCTAssertNil(store.shieldedWebDomains)
    }

    func testClearResetsEverySetting() {
        ShieldWriter.apply(Fixture.profile(restrictWebToAllowlist: true), to: store)
        ShieldWriter.clear(store)

        XCTAssertNil(store.shieldedApplications)
        XCTAssertEqual(store.shieldedCategories, ShieldSettings.ActivityCategoryPolicy.none)
        XCTAssertNil(store.shieldedWebDomains)
        XCTAssertEqual(store.blockedByFilter, WebContentSettings.FilterPolicy.none)
    }

    func testApplyingAnAllowListOverwritesAClearedState() {
        ShieldWriter.clear(store)
        ShieldWriter.apply(Fixture.profile(restrictWebToAllowlist: true), to: store)

        XCTAssertEqual(store.blockedByFilter, .all())
    }
}
