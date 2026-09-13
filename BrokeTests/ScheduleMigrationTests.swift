//
//  ScheduleMigrationTests.swift
//  BrokeTests
//

import XCTest
@testable import Broke

final class ScheduleMigrationTests: BrokeTestCase {
    private let inlineWindowJSON = """
    {
      "id": "22222222-2222-2222-2222-222222222222",
      "name": "School Hours",
      "mode": "block",
      "weekdays": [2, 3, 4, 5, 6],
      "startTime": { "hour": 9, "minute": 30 },
      "endTime": { "hour": 15, "minute": 45 },
      "budgetMinutes": 30,
      "isEnabled": true
    }
    """

    func testScheduleStoredWithAnInlineWindowDecodesToOneWindow() throws {
        let schedule = try JSONDecoder().decode(Schedule.self, from: Data(inlineWindowJSON.utf8))

        XCTAssertEqual(schedule.name, "School Hours")
        XCTAssertEqual(schedule.mode, .block)
        XCTAssertEqual(schedule.weekdays, [2, 3, 4, 5, 6])
        XCTAssertEqual(schedule.budgetMinutes, 30)
        XCTAssertEqual(schedule.windows.count, 1)
        XCTAssertEqual(schedule.windows[0].startMinutes, 9 * 60 + 30)
        XCTAssertEqual(schedule.windows[0].endMinutes, 15 * 60 + 45)
    }

    func testAMigratedScheduleIsValidAndKeepsWorking() throws {
        let schedule = try JSONDecoder().decode(Schedule.self, from: Data(inlineWindowJSON.utf8))

        XCTAssertTrue(schedule.isValid)
        XCTAssertTrue(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 14, 10, 0), calendar: Fixture.calendar))
        XCTAssertFalse(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 14, 16, 0), calendar: Fixture.calendar))
    }

    func testAMigratedScheduleGetsAWindowIdForItsActivity() throws {
        let schedule = try JSONDecoder().decode(Schedule.self, from: Data(inlineWindowJSON.utf8))

        XCTAssertEqual(schedule.windows[0].activityName.rawValue, schedule.windows[0].id.uuidString)
        XCTAssertNotEqual(schedule.windows[0].id, schedule.id)
    }

    func testAProfileStoredWithInlineWindowSchedulesDecodes() throws {
        let json = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "name": "Legacy",
          "appTokens": [],
          "categoryTokens": [],
          "icon": "moon",
          "schedules": [\(inlineWindowJSON)]
        }
        """

        let profile = try JSONDecoder().decode(Profile.self, from: Data(json.utf8))

        XCTAssertEqual(profile.schedules.count, 1)
        XCTAssertEqual(profile.schedules[0].windows.count, 1)
    }

    func testRoundTripKeepsTheWindowList() throws {
        let original = Fixture.schedule(windows: [Fixture.window(6, 0, 8, 0), Fixture.window(20, 0, 22, 0)])

        let decoded = try JSONDecoder().decode(Schedule.self, from: JSONEncoder().encode(original))

        XCTAssertEqual(decoded, original)
    }
}
