//
//  Schedule.swift
//  Broke
//

import Foundation
import DeviceActivity
import ManagedSettings

enum ScheduleMode: String, Codable, CaseIterable, Identifiable {
    case block
    case allow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .block: return "Block"
        case .allow: return "Allow"
        }
    }

    var explanation: String {
        switch self {
        case .block:
            return "This profile is blocked during the window below."
        case .allow:
            return "This profile is only usable during the window below. It's blocked the rest of the day."
        }
    }
}

/// A recurring window in which a profile is blocked or allowed.
///
/// `weekdays` follows `Calendar`'s convention: 1 = Sunday ... 7 = Saturday.
/// `startTime`/`endTime` carry only `hour` and `minute`; a window may not cross
/// midnight, so `endTime` must be later than `startTime` on the same day.
struct Schedule: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var mode: ScheduleMode
    var weekdays: Set<Int>
    var startTime: DateComponents
    var endTime: DateComponents
    var budgetMinutes: Int?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        mode: ScheduleMode,
        weekdays: Set<Int>,
        startTime: DateComponents,
        endTime: DateComponents,
        budgetMinutes: Int? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.weekdays = weekdays
        self.startTime = startTime
        self.endTime = endTime
        self.budgetMinutes = budgetMinutes
        self.isEnabled = isEnabled
    }

    var durationMinutes: Int {
        let start = (startTime.hour ?? 0) * 60 + (startTime.minute ?? 0)
        let end = (endTime.hour ?? 0) * 60 + (endTime.minute ?? 0)
        return end - start
    }

    /// The shortest window DeviceActivityCenter accepts.
    static let minimumDurationMinutes = 15

    var isValid: Bool {
        !weekdays.isEmpty && durationMinutes >= Schedule.minimumDurationMinutes
    }

    // MARK: - Activity and store identity

    /// Each schedule owns its own `DeviceActivityName` and `ManagedSettingsStore`,
    /// keyed by id. A separate named store per schedule means a schedule's shield
    /// composes with every other store (the manual toggle's, other schedules') rather
    /// than overwriting them — `ManagedSettingsStore` settings from different stores
    /// are combined by the system, not last-write-wins.
    var activityName: DeviceActivityName {
        DeviceActivityName(id.uuidString)
    }

    /// Only meaningful for `.allow` — the daily-usage budget event attached to this
    /// schedule's own activity, since the budget and the window cover the same span.
    var budgetEventName: DeviceActivityEvent.Name {
        DeviceActivityEvent.Name(id.uuidString)
    }

    /// Only meaningful for `.block` — a second, all-day activity that tracks usage
    /// outside the blocked window. The window's own activity only covers the window
    /// itself, and `DeviceActivitySchedule` can't express two disjoint spans (before
    /// and after the window) as one interval. An all-day tracker works without
    /// splitting the budget: during the window the profile is already shielded, so no
    /// usage accrues there, leaving the count an accurate measure of outside-window use.
    var outsideWindowActivityName: DeviceActivityName {
        DeviceActivityName("\(id.uuidString)-outside")
    }

    var outsideWindowEventName: DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("\(id.uuidString)-outside")
    }

    var storeName: ManagedSettingsStore.Name {
        ManagedSettingsStore.Name(id.uuidString)
    }

    // MARK: - Scheduling logic (shared by ScheduleManager and the monitor extension)

    func isActiveToday(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        weekdays.contains(calendar.component(.weekday, from: referenceDate))
    }

    func isWithinWindow(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        let now = calendar.dateComponents([.hour, .minute], from: referenceDate)
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        let startMinutes = (startTime.hour ?? 0) * 60 + (startTime.minute ?? 0)
        let endMinutes = (endTime.hour ?? 0) * 60 + (endTime.minute ?? 0)
        return nowMinutes >= startMinutes && nowMinutes < endMinutes
    }

    /// Whether this schedule's window is open right now: today is a scheduled day,
    /// and the current time falls inside the start/end window.
    func isUsable(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        isActiveToday(referenceDate: referenceDate, calendar: calendar)
            && isWithinWindow(referenceDate: referenceDate, calendar: calendar)
    }

    /// Whether this schedule wants its profile blocked right now, independent of
    /// `isEnabled` and any NFC suspension — callers layer those in separately.
    /// `.block` blocks exactly during the window; `.allow` blocks everywhere else.
    func wantsBlock(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        let usable = isUsable(referenceDate: referenceDate, calendar: calendar)
        return mode == .block ? usable : !usable
    }

    /// `wantsBlock()`, plus: for `.block` mode, staying blocked for the rest of today
    /// if the outside-window budget was already spent, even after the window itself
    /// has ended — otherwise the window closing would unconditionally clear a block
    /// the budget is still supposed to be enforcing.
    func effectiveWantsBlock(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        if wantsBlock(referenceDate: referenceDate, calendar: calendar) { return true }
        guard mode == .block, isActiveToday(referenceDate: referenceDate, calendar: calendar) else { return false }
        return SharedStore.isOutsideWindowBudgetExceeded(for: id)
    }
}
