//
//  BrokeTestSupport.swift
//  BrokeTests
//

import DeviceActivity
import Foundation
import ManagedSettings
import XCTest
@testable import Broke

/// Points `SharedStore` at a scratch suite and `ScheduleManager` at recorders, then puts both back.
class BrokeTestCase: XCTestCase {
    private static let suiteName = "com.Brokeest.ios.tests"

    private var originalDefaults: UserDefaults!
    private var originalCenter: ActivityRegistering!
    private var originalShieldTarget: ((ManagedSettingsStore.Name) -> ShieldTarget)!

    var center: RecordingActivityCenter!
    var stores: ShieldTargetRegistry!

    override func setUp() {
        super.setUp()

        originalDefaults = SharedStore.defaults
        let scratch = UserDefaults(suiteName: Self.suiteName)!
        scratch.removePersistentDomain(forName: Self.suiteName)
        SharedStore.defaults = scratch

        originalCenter = ScheduleManager.center
        originalShieldTarget = ScheduleManager.shieldTarget
        center = RecordingActivityCenter()
        stores = ShieldTargetRegistry()
        ScheduleManager.center = center
        ScheduleManager.shieldTarget = { [stores] name in stores!.target(named: name) }
    }

    override func tearDown() {
        SharedStore.defaults.removePersistentDomain(forName: Self.suiteName)
        SharedStore.defaults = originalDefaults
        ScheduleManager.center = originalCenter
        ScheduleManager.shieldTarget = originalShieldTarget
        center = nil
        stores = nil
        super.tearDown()
    }
}

// MARK: - Recorders

final class RecordingShieldTarget: ShieldTarget {
    var shieldedApplications: Set<ApplicationToken>?
    var shieldedCategories: ShieldSettings.ActivityCategoryPolicy<Application>?
    var shieldedWebDomains: Set<WebDomainToken>?
    var blockedByFilter: WebContentSettings.FilterPolicy?
}

/// Hands out one recorder per store name. Every token set a test can build is empty, so a
/// profile with `restrictWebToAllowlist` is what tells an applied shield from a cleared one:
/// applying writes `.all()`, clearing writes `.none`.
final class ShieldTargetRegistry {
    private(set) var requestedNames: [String] = []
    private var targets: [String: RecordingShieldTarget] = [:]

    func target(named name: ManagedSettingsStore.Name) -> ShieldTarget {
        requestedNames.append(name.rawValue)
        return recorder(for: name.rawValue)
    }

    func recorder(for name: String) -> RecordingShieldTarget {
        if let existing = targets[name] { return existing }
        let created = RecordingShieldTarget()
        targets[name] = created
        return created
    }

    func filter(for name: String) -> WebContentSettings.FilterPolicy? {
        targets[name]?.blockedByFilter
    }
}

final class RecordingActivityCenter: ActivityRegistering {
    private(set) var stopCount = 0
    private(set) var startedActivities: [String] = []

    func stopMonitoring(_ activities: [DeviceActivityName]) {
        stopCount += 1
    }

    func startMonitoring(
        _ activity: DeviceActivityName,
        during schedule: DeviceActivitySchedule,
        events: [DeviceActivityEvent.Name: DeviceActivityEvent]
    ) throws {
        startedActivities.append(activity.rawValue)
    }
}

// MARK: - Builders

enum Fixture {
    /// UTC so a weekday and a minute-of-day never depend on where the test runs.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    static func time(_ hour: Int, _ minute: Int) -> DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    static let everyDay: Set<Int> = [1, 2, 3, 4, 5, 6, 7]

    static func schedule(
        id: UUID = UUID(),
        name: String = "Test",
        mode: ScheduleMode = .block,
        weekdays: Set<Int> = everyDay,
        start: DateComponents = time(9, 0),
        end: DateComponents = time(17, 0),
        budgetMinutes: Int? = nil,
        isEnabled: Bool = true
    ) -> Schedule {
        Schedule(
            id: id,
            name: name,
            mode: mode,
            weekdays: weekdays,
            startTime: start,
            endTime: end,
            budgetMinutes: budgetMinutes,
            isEnabled: isEnabled
        )
    }

    static func profile(
        name: String = "Work",
        schedules: [Schedule] = [],
        restrictWebToAllowlist: Bool = false,
        icon: String = "bell.slash"
    ) -> Profile {
        Profile(
            name: name,
            appTokens: [],
            categoryTokens: [],
            webDomainTokens: [],
            schedules: schedules,
            restrictWebToAllowlist: restrictWebToAllowlist,
            icon: icon
        )
    }

    private static var currentMinuteOfDay: Int {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (now.hour ?? 0) * 60 + (now.minute ?? 0)
    }

    /// A window the real clock is inside right now, for the paths that read `Date()` directly.
    /// Returns nil in the final minute of the day, where no same-day window can contain now.
    static func windowCoveringNow() -> (start: DateComponents, end: DateComponents)? {
        let minute = currentMinuteOfDay
        let start = max(0, minute - 30)
        let end = min(1439, start + 120)
        guard end > minute, end - start >= Schedule.minimumDurationMinutes else { return nil }
        return (time(start / 60, start % 60), time(end / 60, end % 60))
    }

    /// A valid window the real clock is outside of right now.
    static func windowExcludingNow() -> (start: DateComponents, end: DateComponents) {
        currentMinuteOfDay < 720 ? (time(20, 0), time(22, 0)) : (time(1, 0), time(3, 0))
    }
}

/// Keys `SharedStore` persists under. Tests write them directly to reach dates it only ever stamps as today.
enum StoreKey {
    static let isBlocking = "isBlocking"
    static let emergencyUsedDate = "emergencyUnblocksUsedDateKey"
    static let emergencyUsedCount = "emergencyUnblocksUsedCountKey"

    static func outsideWindowBudget(_ id: UUID) -> String {
        "outsideWindowBudgetExceededDate-\(id.uuidString)"
    }
}
