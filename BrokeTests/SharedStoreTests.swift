//
//  SharedStoreTests.swift
//  BrokeTests
//

import DeviceActivity
import XCTest
@testable import Broke

final class SharedStoreTests: BrokeTestCase {
    // MARK: - Suspension

    func testSuspensionHoldsUntilItsDeadline() {
        SharedStore.beginSuspension(until: Date().addingTimeInterval(600))
        XCTAssertTrue(SharedStore.isSuspended)

        SharedStore.clearSuspension()
        XCTAssertFalse(SharedStore.isSuspended)
        XCTAssertNil(SharedStore.suspendedUntil)
    }

    func testSuspensionInThePastIsOver() {
        SharedStore.beginSuspension(until: Date().addingTimeInterval(-1))
        XCTAssertFalse(SharedStore.isSuspended)
    }

    // MARK: - Emergency unblocks

    func testEmergencyAllowanceStartsFull() {
        XCTAssertEqual(SharedStore.emergencyUnblocksUsedThisMonth, 0)
        XCTAssertEqual(SharedStore.remainingEmergencyUnblocks, SharedStore.maximumEmergencyUnblocks)
    }

    func testRecordingAnEmergencyUnblockSpendsOne() {
        SharedStore.recordEmergencyUnblock()
        SharedStore.recordEmergencyUnblock()

        XCTAssertEqual(SharedStore.emergencyUnblocksUsedThisMonth, 2)
        XCTAssertEqual(SharedStore.remainingEmergencyUnblocks, SharedStore.maximumEmergencyUnblocks - 2)
    }

    func testAllowanceRefillsWhenTheStampIsFromAnEarlierMonth() {
        let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date())!
        SharedStore.defaults.set(lastMonth, forKey: StoreKey.emergencyUsedDate)
        SharedStore.defaults.set(SharedStore.maximumEmergencyUnblocks, forKey: StoreKey.emergencyUsedCount)

        XCTAssertEqual(SharedStore.emergencyUnblocksUsedThisMonth, 0)
        XCTAssertEqual(SharedStore.remainingEmergencyUnblocks, SharedStore.maximumEmergencyUnblocks)
    }

    func testAllowanceNeverGoesNegative() {
        SharedStore.defaults.set(Date(), forKey: StoreKey.emergencyUsedDate)
        SharedStore.defaults.set(SharedStore.maximumEmergencyUnblocks + 3, forKey: StoreKey.emergencyUsedCount)

        XCTAssertEqual(SharedStore.remainingEmergencyUnblocks, 0)
    }

    // MARK: - Outside-window budget

    func testBudgetFlagAppliesOnlyToTheDayItWasStamped() {
        let id = UUID()
        SharedStore.setBudgetSpent(true, for: id)
        XCTAssertTrue(SharedStore.isBudgetSpent(for: id))

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        SharedStore.defaults.set(yesterday, forKey: StoreKey.budgetSpent(id))
        XCTAssertFalse(SharedStore.isBudgetSpent(for: id))
    }

    func testBudgetFlagIsPerSchedule() {
        let spent = UUID()
        SharedStore.setBudgetSpent(true, for: spent)

        XCTAssertTrue(SharedStore.isBudgetSpent(for: spent))
        XCTAssertFalse(SharedStore.isBudgetSpent(for: UUID()))
    }

    // MARK: - Profile editing grant

    func testGrantOpensEditingAndRevokeClosesIt() {
        SharedStore.grantProfileEditAccess()
        XCTAssertTrue(SharedStore.isProfileEditingUnlocked)

        SharedStore.revokeProfileEditAccess()
        XCTAssertFalse(SharedStore.isProfileEditingUnlocked)
    }

    func testEditingStaysLockedWhileAnythingIsBlocking() {
        SharedStore.grantProfileEditAccess()
        SharedStore.defaults.set(true, forKey: StoreKey.isBlocking)

        XCTAssertTrue(SharedStore.isManuallyBlocking)
        XCTAssertTrue(SharedStore.isAnythingBlocking)
        XCTAssertFalse(SharedStore.isProfileEditingUnlocked)
    }

    func testEditingIsLockedWithoutAGrant() {
        XCTAssertFalse(SharedStore.isProfileEditingUnlocked)
    }

    // MARK: - Active schedules

    func testActiveBlockingSchedulesReturnsOnlyTheOnesThatWantABlock() throws {
        let covering = try XCTUnwrap(Fixture.windowCoveringNow(), "no same-day window contains this minute")
        let excluding = Fixture.windowExcludingNow()

        let blocking = Fixture.schedule(name: "Now", start: covering.start, end: covering.end)
        let idle = Fixture.schedule(name: "Later", start: excluding.start, end: excluding.end)
        SharedStore.saveProfiles([Fixture.profile(schedules: [blocking, idle])])

        XCTAssertEqual(SharedStore.activeBlockingSchedules().map(\.name), ["Now"])
        XCTAssertTrue(SharedStore.isAnyScheduleBlocking())
    }

    func testDisabledAndInvalidSchedulesNeverBlock() throws {
        let covering = try XCTUnwrap(Fixture.windowCoveringNow(), "no same-day window contains this minute")

        let disabled = Fixture.schedule(name: "Disabled", start: covering.start, end: covering.end, isEnabled: false)
        let tooShort = Fixture.schedule(name: "Short", start: covering.start, end: covering.start)
        SharedStore.saveProfiles([Fixture.profile(schedules: [disabled, tooShort])])

        XCTAssertEqual(SharedStore.activeBlockingSchedules().count, 0)
        XCTAssertFalse(SharedStore.isAnythingBlocking)
    }

    func testASuspensionSilencesEverySchedule() throws {
        let covering = try XCTUnwrap(Fixture.windowCoveringNow(), "no same-day window contains this minute")
        SharedStore.saveProfiles([Fixture.profile(schedules: [Fixture.schedule(start: covering.start, end: covering.end)])])
        XCTAssertEqual(SharedStore.activeBlockingSchedules().count, 1)

        SharedStore.beginSuspension(until: Date().addingTimeInterval(600))

        XCTAssertEqual(SharedStore.activeBlockingSchedules().count, 0)
    }

    // MARK: - Schedule lookup

    func testScheduleLookupFindsTheOwningProfile() throws {
        let target = Fixture.schedule(name: "Evenings")
        SharedStore.saveProfiles([
            Fixture.profile(name: "First", schedules: [Fixture.schedule(name: "Other")]),
            Fixture.profile(name: "Second", schedules: [target]),
        ])

        let found = try XCTUnwrap(SharedStore.schedule(withId: target.id))

        XCTAssertEqual(found.profile.name, "Second")
        XCTAssertEqual(found.schedule.name, "Evenings")
    }

    func testWindowLookupFindsItsScheduleAndProfile() throws {
        let target = Fixture.schedule(name: "Split", windows: [Fixture.window(6, 0, 8, 0), Fixture.window(20, 0, 22, 0)])
        SharedStore.saveProfiles([
            Fixture.profile(name: "First", schedules: [Fixture.schedule(name: "Other")]),
            Fixture.profile(name: "Second", schedules: [target]),
        ])

        let found = try XCTUnwrap(SharedStore.window(withId: target.windows[1].id))

        XCTAssertEqual(found.profile.name, "Second")
        XCTAssertEqual(found.schedule.id, target.id)
        XCTAssertEqual(found.window.id, target.windows[1].id)
    }

    func testWindowLookupReturnsNilForAnUnknownId() {
        SharedStore.saveProfiles([Fixture.profile(schedules: [Fixture.schedule()])])
        XCTAssertNil(SharedStore.window(withId: UUID()))
    }

    func testScheduleLookupReturnsNilForAnUnknownId() {
        SharedStore.saveProfiles([Fixture.profile(schedules: [Fixture.schedule()])])
        XCTAssertNil(SharedStore.schedule(withId: UUID()))
    }

    func testBudgetActivityNameResolvesToItsSchedule() throws {
        let target = Fixture.schedule(name: "Evenings")
        SharedStore.saveProfiles([Fixture.profile(schedules: [target])])

        let found = try XCTUnwrap(SharedStore.schedule(forBudgetActivity: target.budgetActivityName))

        XCTAssertEqual(found.schedule.id, target.id)
    }

    func testAPlainActivityNameIsNotTreatedAsABudgetOne() {
        let target = Fixture.schedule()
        SharedStore.saveProfiles([Fixture.profile(schedules: [target])])

        XCTAssertNil(SharedStore.schedule(forBudgetActivity: target.windows[0].activityName))
    }

    // MARK: - Known schedule ids

    func testKnownScheduleIdsRoundTrip() {
        let ids: Set<UUID> = [UUID(), UUID()]
        SharedStore.setKnownScheduleIds(ids)

        XCTAssertEqual(SharedStore.knownScheduleIds(), ids)
    }

    // MARK: - Install identity

    func testInstallIdentifierIsStable() {
        XCTAssertEqual(SharedStore.installIdentifier, SharedStore.installIdentifier)
    }

    // MARK: - Log buffer

    func testLogBufferKeepsTheMostRecentLinesOnly() {
        let overflow = SharedStore.maximumStoredLogLines + 50
        for index in 0..<overflow {
            SharedStore.appendLogLine("line \(index)")
        }

        let lines = SharedStore.recentLogLines
        XCTAssertEqual(lines.count, SharedStore.maximumStoredLogLines)
        XCTAssertEqual(lines.last, "line \(overflow - 1)")
        XCTAssertEqual(lines.first, "line \(overflow - SharedStore.maximumStoredLogLines)")
    }

    func testClearingTheLogBufferEmptiesIt() {
        SharedStore.appendLogLine("something")
        SharedStore.clearLogLines()

        XCTAssertEqual(SharedStore.recentLogLines, [])
    }
}
