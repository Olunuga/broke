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

    func testSpentLimitKeepsABlockScheduleBlockingAfterItsWindow() {
        let schedule = Fixture.schedule(mode: .block, weekdays: Fixture.everyDay, start: Fixture.time(0, 0), end: Fixture.time(0, 15))
        SharedStore.setBudgetSpent(true, for: schedule.id)

        XCTAssertFalse(schedule.wantsBlock(referenceDate: Date()))
        XCTAssertTrue(schedule.effectiveWantsBlock(referenceDate: Date()))
    }

    func testSpentLimitBlocksAnAllowScheduleInsideItsWindow() {
        let schedule = Fixture.schedule(mode: .allow, weekdays: Fixture.everyDay, start: Fixture.time(0, 0), end: Fixture.time(23, 59))
        SharedStore.setBudgetSpent(true, for: schedule.id)

        XCTAssertFalse(schedule.wantsBlock(referenceDate: Date()))
        XCTAssertTrue(schedule.effectiveWantsBlock(referenceDate: Date()))
    }

    func testSpentLimitDoesNotBlockOnADayTheScheduleDoesNotRun() {
        let schedule = Fixture.schedule(mode: .block, weekdays: [2], start: Fixture.time(9, 0), end: Fixture.time(17, 0))
        SharedStore.setBudgetSpent(true, for: schedule.id)

        XCTAssertFalse(schedule.effectiveWantsBlock(referenceDate: sunday, calendar: calendar))
    }

    func testClearedLimitStopsEnforcing() {
        let schedule = Fixture.schedule(mode: .block, weekdays: Fixture.everyDay, start: Fixture.time(0, 0), end: Fixture.time(0, 15))
        SharedStore.setBudgetSpent(true, for: schedule.id)
        SharedStore.setBudgetSpent(false, for: schedule.id)

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

    // MARK: - Several windows in one schedule

    private var morningAndEvening: [ScheduleWindow] {
        [Fixture.window(6, 0, 8, 0), Fixture.window(20, 0, 22, 0)]
    }

    func testAWindowIsOpenInsideEitherSpanAndNotBetweenThem() {
        let schedule = Fixture.schedule(weekdays: [2], windows: morningAndEvening)

        XCTAssertTrue(schedule.isUsable(referenceDate: Fixture.date(2026, 9, 14, 7, 0), calendar: calendar))
        XCTAssertTrue(schedule.isUsable(referenceDate: Fixture.date(2026, 9, 14, 21, 0), calendar: calendar))
        XCTAssertFalse(schedule.isUsable(referenceDate: Fixture.date(2026, 9, 14, 12, 0), calendar: calendar))
    }

    func testBlockModeBlocksInEveryWindow() {
        let schedule = Fixture.schedule(mode: .block, weekdays: [2], windows: morningAndEvening)

        XCTAssertTrue(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 14, 7, 0), calendar: calendar))
        XCTAssertTrue(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 14, 21, 0), calendar: calendar))
        XCTAssertFalse(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 14, 12, 0), calendar: calendar))
    }

    func testAllowModeAllowsInEveryWindowAndBlocksBetweenThem() {
        let schedule = Fixture.schedule(mode: .allow, weekdays: [2], windows: morningAndEvening)

        XCTAssertFalse(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 14, 7, 0), calendar: calendar))
        XCTAssertFalse(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 14, 21, 0), calendar: calendar))
        XCTAssertTrue(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 14, 12, 0), calendar: calendar))
        XCTAssertTrue(schedule.wantsBlock(referenceDate: Fixture.date(2026, 9, 13, 7, 0), calendar: calendar))
    }

    func testDurationIsTheTotalOfEveryWindow() {
        XCTAssertEqual(Fixture.schedule(windows: morningAndEvening).durationMinutes, 240)
    }

    func testNextTransitionPicksTheNearestBoundaryAcrossWindows() {
        let schedule = Fixture.schedule(weekdays: [2], windows: morningAndEvening)

        XCTAssertEqual(
            schedule.nextTransition(referenceDate: Fixture.date(2026, 9, 14, 9, 0), calendar: calendar),
            Fixture.date(2026, 9, 14, 20, 0)
        )
        XCTAssertEqual(
            schedule.nextTransition(referenceDate: Fixture.date(2026, 9, 14, 7, 0), calendar: calendar),
            Fixture.date(2026, 9, 14, 8, 0)
        )
    }

    // MARK: - Validity across windows

    func testOverlappingWindowsAreInvalid() {
        let schedule = Fixture.schedule(windows: [Fixture.window(9, 0, 12, 0), Fixture.window(11, 0, 14, 0)])

        XCTAssertTrue(schedule.hasOverlappingWindows)
        XCTAssertFalse(schedule.isValid)
    }

    func testWindowsThatTouchWithoutOverlappingAreValid() {
        let schedule = Fixture.schedule(windows: [Fixture.window(9, 0, 12, 0), Fixture.window(12, 0, 14, 0)])

        XCTAssertFalse(schedule.hasOverlappingWindows)
        XCTAssertTrue(schedule.isValid)
    }

    func testOneWindowUnderTheMinimumMakesTheWholeScheduleInvalid() {
        let schedule = Fixture.schedule(windows: [Fixture.window(9, 0, 12, 0), Fixture.window(20, 0, 20, 10)])

        XCTAssertFalse(schedule.isValid)
    }

    func testScheduleWithNoWindowsIsInvalid() {
        XCTAssertFalse(Fixture.schedule(windows: []).isValid)
    }

    func testSortedWindowsOrdersByStart() {
        let schedule = Fixture.schedule(windows: [Fixture.window(20, 0, 22, 0), Fixture.window(6, 0, 8, 0)])

        XCTAssertEqual(schedule.sortedWindows.map(\.startMinutes), [360, 1200])
    }

    // MARK: - Activity names

    func testEachWindowCarriesItsOwnActivityName() {
        let schedule = Fixture.schedule(windows: morningAndEvening)
        let names = schedule.windows.map(\.activityName.rawValue)

        XCTAssertEqual(Set(names).count, 2)
        XCTAssertEqual(names, schedule.windows.map(\.id.uuidString))
    }

    func testBudgetActivityIsNamedForTheSchedule() {
        let schedule = Fixture.schedule()

        XCTAssertEqual(schedule.budgetActivityName.rawValue, "\(schedule.id.uuidString)-budget")
        XCTAssertEqual(schedule.storeName.rawValue, schedule.id.uuidString)
    }
}
