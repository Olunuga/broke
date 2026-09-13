//
//  ScheduleTests.swift
//  BrokeTests
//

import XCTest
@testable import Broke

final class ScheduleTests: BrokeTestCase {
    private let calendar = Fixture.calendar

    // 2026-09-14 is a Monday, weekday 2. 2026-09-13 is a Sunday, weekday 1.
    private let monday = Fixture.date(2026, 9, 14, 12, 0)
    private let sunday = Fixture.date(2026, 9, 13, 12, 0)

    // MARK: - Validity

    func testDurationMinutesMeasuresTheWindow() {
        let schedule = Fixture.schedule(start: Fixture.time(9, 30), end: Fixture.time(17, 15))
        XCTAssertEqual(schedule.durationMinutes, 465)
    }

    func testWindowShorterThanTheMinimumIsInvalid() {
        let schedule = Fixture.schedule(start: Fixture.time(9, 0), end: Fixture.time(9, 14))
        XCTAssertFalse(schedule.isValid)
    }

    func testWindowAtExactlyTheMinimumIsValid() {
        let schedule = Fixture.schedule(start: Fixture.time(9, 0), end: Fixture.time(9, 15))
        XCTAssertTrue(schedule.isValid)
    }

    func testScheduleWithNoWeekdaysIsInvalid() {
        XCTAssertFalse(Fixture.schedule(weekdays: []).isValid)
    }

    // MARK: - Window boundaries

    func testWindowIncludesItsStartMinute() {
        let schedule = Fixture.schedule(start: Fixture.time(9, 0), end: Fixture.time(17, 0))
        XCTAssertTrue(schedule.isWithinWindow(referenceDate: Fixture.date(2026, 9, 14, 9, 0), calendar: calendar))
    }

    func testWindowExcludesItsEndMinute() {
        let schedule = Fixture.schedule(start: Fixture.time(9, 0), end: Fixture.time(17, 0))
        XCTAssertFalse(schedule.isWithinWindow(referenceDate: Fixture.date(2026, 9, 14, 17, 0), calendar: calendar))
        XCTAssertTrue(schedule.isWithinWindow(referenceDate: Fixture.date(2026, 9, 14, 16, 59), calendar: calendar))
    }

    func testIsActiveTodayFollowsCalendarWeekdayNumbers() {
        let weekdaysOnly = Fixture.schedule(weekdays: [2, 3, 4, 5, 6])
        XCTAssertTrue(weekdaysOnly.isActiveToday(referenceDate: monday, calendar: calendar))
        XCTAssertFalse(weekdaysOnly.isActiveToday(referenceDate: sunday, calendar: calendar))
    }

    func testIsUsableNeedsBothTheDayAndTheWindow() {
        let schedule = Fixture.schedule(weekdays: [2], start: Fixture.time(9, 0), end: Fixture.time(17, 0))
        XCTAssertTrue(schedule.isUsable(referenceDate: Fixture.date(2026, 9, 14, 10, 0), calendar: calendar))
        XCTAssertFalse(schedule.isUsable(referenceDate: Fixture.date(2026, 9, 14, 18, 0), calendar: calendar))
        XCTAssertFalse(schedule.isUsable(referenceDate: Fixture.date(2026, 9, 13, 10, 0), calendar: calendar))
    }

    // MARK: - Mode semantics

    func testBlockModeBlocksInsideTheWindowOnly() {
        let schedule = Fixture.schedule(mode: .block, weekdays: [2], start: Fixture.time(9, 0), end: Fixture.time(17, 0))
        XCTAssertTrue(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 14, 10, 0), calendar: calendar))
        XCTAssertFalse(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 14, 18, 0), calendar: calendar))
    }

    func testBlockModeDoesNotBlockOnADayItDoesNotRun() {
        let schedule = Fixture.schedule(mode: .block, weekdays: [2], start: Fixture.time(9, 0), end: Fixture.time(17, 0))
        XCTAssertFalse(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 13, 10, 0), calendar: calendar))
    }

    func testAllowModeBlocksOutsideTheWindow() {
        let schedule = Fixture.schedule(mode: .allow, weekdays: [2], start: Fixture.time(9, 0), end: Fixture.time(17, 0))
        XCTAssertFalse(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 14, 10, 0), calendar: calendar))
        XCTAssertTrue(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 14, 18, 0), calendar: calendar))
    }

    func testAllowModeBlocksAllDayOnADayItDoesNotRun() {
        let schedule = Fixture.schedule(mode: .allow, weekdays: [2], start: Fixture.time(9, 0), end: Fixture.time(17, 0))
        XCTAssertTrue(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 13, 10, 0), calendar: calendar))
        XCTAssertTrue(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 13, 23, 0), calendar: calendar))
    }

    // MARK: - Outside-window budget

    func testSpentOutsideWindowBudgetKeepsABlockScheduleBlockingAfterItsWindow() {
        let schedule = Fixture.schedule(mode: .block, weekdays: Fixture.everyDay, start: Fixture.time(0, 0), end: Fixture.time(0, 15))
        SharedStore.setOutsideWindowBudgetExceeded(true, for: schedule.id)

        XCTAssertFalse(schedule.wantsBlock(referenceDate: Date()))
        XCTAssertTrue(schedule.effectiveWantsBlock(referenceDate: Date()))
    }

    func testSpentBudgetDoesNotAffectAnAllowSchedule() {
        let schedule = Fixture.schedule(mode: .allow, weekdays: Fixture.everyDay, start: Fixture.time(0, 0), end: Fixture.time(23, 59))
        SharedStore.setOutsideWindowBudgetExceeded(true, for: schedule.id)

        // `.allow` inside its window wants no block, and the budget flag is a `.block` concern.
        XCTAssertEqual(schedule.effectiveWantsBlock(referenceDate: Date()), schedule.wantsBlock(referenceDate: Date()))
    }

    func testSpentBudgetDoesNotBlockOnADayTheScheduleDoesNotRun() {
        let schedule = Fixture.schedule(mode: .block, weekdays: [2], start: Fixture.time(9, 0), end: Fixture.time(17, 0))
        SharedStore.setOutsideWindowBudgetExceeded(true, for: schedule.id)

        XCTAssertFalse(schedule.effectiveWantsBlock(referenceDate: sunday, calendar: calendar))
    }

    func testClearedBudgetStopsEnforcing() {
        let schedule = Fixture.schedule(mode: .block, weekdays: Fixture.everyDay, start: Fixture.time(0, 0), end: Fixture.time(0, 15))
        SharedStore.setOutsideWindowBudgetExceeded(true, for: schedule.id)
        SharedStore.setOutsideWindowBudgetExceeded(false, for: schedule.id)

        XCTAssertFalse(schedule.effectiveWantsBlock(referenceDate: Date()))
    }

    // MARK: - Next transition

    func testNextTransitionIsTheNearestBoundaryLaterToday() {
        let schedule = Fixture.schedule(weekdays: [2], start: Fixture.time(9, 0), end: Fixture.time(17, 0))
        let next = schedule.nextTransition(referenceDate: Fixture.date(2026, 9, 14, 10, 0), calendar: calendar)
        XCTAssertEqual(next, Fixture.date(2026, 9, 14, 17, 0))
    }

    func testNextTransitionSkipsDaysTheScheduleDoesNotRunOn() {
        let schedule = Fixture.schedule(weekdays: [2], start: Fixture.time(9, 0), end: Fixture.time(17, 0))
        let next = schedule.nextTransition(referenceDate: Fixture.date(2026, 9, 14, 18, 0), calendar: calendar)
        XCTAssertEqual(next, Fixture.date(2026, 9, 21, 9, 0))
    }

    func testNextTransitionIsNilWhenNoDayIsScheduled() {
        let schedule = Fixture.schedule(weekdays: [], start: Fixture.time(9, 0), end: Fixture.time(17, 0))
        XCTAssertNil(schedule.nextTransition(referenceDate: monday, calendar: calendar))
    }
}
