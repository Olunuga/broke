//
//  ScheduleSyncTests.swift
//  BrokeTests
//

import ManagedSettings
import XCTest
@testable import Broke

/// Every profile here uses `restrictWebToAllowlist` with no allowed sites. A test cannot
/// build an `ApplicationToken`, so `.all()` against `.none` on the web filter is what
/// separates a store `sync` shielded from one it cleared.
final class ScheduleSyncTests: BrokeTestCase {
    private func isShielded(_ schedule: Schedule) -> Bool {
        stores.filter(for: schedule.id.uuidString) == .all()
    }

    private func isCleared(_ schedule: Schedule) -> Bool {
        stores.filter(for: schedule.id.uuidString) == WebContentSettings.FilterPolicy.none
    }

    func testSyncShieldsOnlyTheSchedulesThatWantABlock() throws {
        let covering = try XCTUnwrap(Fixture.windowCoveringNow(), "no same-day window contains this minute")
        let excluding = Fixture.windowExcludingNow()

        let active = Fixture.schedule(name: "Now", start: covering.start, end: covering.end)
        let idle = Fixture.schedule(name: "Later", start: excluding.start, end: excluding.end)
        let profile = Fixture.profile(schedules: [active, idle], restrictWebToAllowlist: true)

        ScheduleManager.sync(profiles: [profile])

        XCTAssertTrue(isShielded(active))
        XCTAssertTrue(isCleared(idle))
    }

    func testSyncRegistersOnlyEnabledValidSchedules() throws {
        let covering = try XCTUnwrap(Fixture.windowCoveringNow(), "no same-day window contains this minute")

        let enabled = Fixture.schedule(name: "Enabled", start: covering.start, end: covering.end)
        let disabled = Fixture.schedule(name: "Disabled", start: covering.start, end: covering.end, isEnabled: false)
        let tooShort = Fixture.schedule(name: "Short", start: covering.start, end: covering.start)

        ScheduleManager.sync(profiles: [Fixture.profile(schedules: [enabled, disabled, tooShort])])

        XCTAssertTrue(center.startedActivities.contains(enabled.activityName.rawValue))
        XCTAssertFalse(center.startedActivities.contains(disabled.activityName.rawValue))
        XCTAssertFalse(center.startedActivities.contains(tooShort.activityName.rawValue))
    }

    func testSyncStopsEverythingBeforeReRegistering() {
        ScheduleManager.sync(profiles: [Fixture.profile(schedules: [Fixture.schedule()])])

        XCTAssertEqual(center.stopCount, 1)
    }

    func testADisabledScheduleHasItsShieldCleared() throws {
        let covering = try XCTUnwrap(Fixture.windowCoveringNow(), "no same-day window contains this minute")
        let disabled = Fixture.schedule(name: "Disabled", start: covering.start, end: covering.end, isEnabled: false)

        ScheduleManager.sync(profiles: [Fixture.profile(schedules: [disabled], restrictWebToAllowlist: true)])

        XCTAssertTrue(isCleared(disabled))
    }

    func testASuspensionClearsEveryShield() throws {
        let covering = try XCTUnwrap(Fixture.windowCoveringNow(), "no same-day window contains this minute")
        let active = Fixture.schedule(name: "Now", start: covering.start, end: covering.end)
        let profile = Fixture.profile(schedules: [active], restrictWebToAllowlist: true)

        SharedStore.beginSuspension(until: Date().addingTimeInterval(600))
        ScheduleManager.sync(profiles: [profile])

        XCTAssertTrue(isCleared(active))
    }

    func testSyncClearsTheStoreOfAScheduleThatIsGone() {
        let removedId = UUID()
        SharedStore.setKnownScheduleIds([removedId])

        ScheduleManager.sync(profiles: [Fixture.profile()])

        XCTAssertTrue(stores.requestedNames.contains(removedId.uuidString))
        XCTAssertEqual(stores.filter(for: removedId.uuidString), WebContentSettings.FilterPolicy.none)
    }

    func testSyncRecordsTheScheduleIdsItSaw() {
        let schedule = Fixture.schedule()

        ScheduleManager.sync(profiles: [Fixture.profile(schedules: [schedule])])

        XCTAssertEqual(SharedStore.knownScheduleIds(), [schedule.id])
    }

    func testSuspendingActiveSchedulesStoresTheDeadline() {
        ScheduleManager.suspendActiveSchedules(for: 600, profiles: [Fixture.profile()])

        XCTAssertTrue(SharedStore.isSuspended)
    }

    func testEmergencyUnblockSpendsOneAndSuspends() {
        XCTAssertTrue(ScheduleManager.useEmergencyUnblock(profiles: [Fixture.profile()]))

        XCTAssertTrue(SharedStore.isSuspended)
        XCTAssertEqual(SharedStore.remainingEmergencyUnblocks, SharedStore.maximumEmergencyUnblocks - 1)
    }

    func testEmergencyUnblockIsRefusedOnceTheMonthIsSpent() {
        for _ in 0..<SharedStore.maximumEmergencyUnblocks {
            _ = ScheduleManager.useEmergencyUnblock(profiles: [Fixture.profile()])
        }
        SharedStore.clearSuspension()

        XCTAssertFalse(ScheduleManager.useEmergencyUnblock(profiles: [Fixture.profile()]))
        XCTAssertFalse(SharedStore.isSuspended)
    }
}
