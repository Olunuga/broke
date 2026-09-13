//
//  ProfileCodingTests.swift
//  BrokeTests
//

import XCTest
@testable import Broke

final class ProfileCodingTests: BrokeTestCase {
    func testProfileSavedBeforeTheNewerKeysExistedStillDecodes() throws {
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Legacy",
          "appTokens": [],
          "categoryTokens": [],
          "icon": "moon"
        }
        """

        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))

        XCTAssertEqual(profile.name, "Legacy")
        XCTAssertEqual(profile.icon, "moon")
        XCTAssertEqual(profile.webDomainTokens, [])
        XCTAssertEqual(profile.schedules, [])
        XCTAssertFalse(profile.restrictWebToAllowlist)
    }

    func testRoundTripKeepsIdentityAndSchedules() throws {
        let schedule = Fixture.schedule(name: "Evenings", mode: .allow, weekdays: [2, 4], budgetMinutes: 30)
        let original = Fixture.profile(name: "Focus", schedules: [schedule], restrictWebToAllowlist: true, icon: "book")

        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, "Focus")
        XCTAssertEqual(decoded.icon, "book")
        XCTAssertTrue(decoded.restrictWebToAllowlist)
        XCTAssertEqual(decoded.schedules, [schedule])
    }

    func testDefaultProfileIsRecognisedByName() {
        XCTAssertTrue(Fixture.profile(name: "Default").isDefault)
        XCTAssertFalse(Fixture.profile(name: "Default 2").isDefault)
    }

    func testSavedProfilesRoundTripThroughSharedStore() {
        let profiles = [Fixture.profile(name: "A"), Fixture.profile(name: "B", schedules: [Fixture.schedule()])]
        SharedStore.saveProfiles(profiles)

        let loaded = SharedStore.loadProfiles()

        XCTAssertEqual(loaded.map(\.name), ["A", "B"])
        XCTAssertEqual(loaded[1].schedules, profiles[1].schedules)
    }

    func testLoadProfilesIsEmptyWhenNothingIsStored() {
        XCTAssertEqual(SharedStore.loadProfiles().count, 0)
    }
}
