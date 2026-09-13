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
            return "This profile is blocked during the windows below."
        case .allow:
            return "This profile is usable only inside the windows below, on the days you pick. It stays blocked at every other time, including whole days you do not pick."
        }
    }
}

/// One span of a day. A window may not cross midnight; an overnight span is two windows in the same schedule.
struct ScheduleWindow: Codable, Identifiable, Equatable {
    let id: UUID
    var startTime: DateComponents
    var endTime: DateComponents

    init(id: UUID = UUID(), startTime: DateComponents, endTime: DateComponents) {
        self.id = id
        self.startTime = startTime
        self.endTime = endTime
    }

    var startMinutes: Int { (startTime.hour ?? 0) * 60 + (startTime.minute ?? 0) }

    var endMinutes: Int { (endTime.hour ?? 0) * 60 + (endTime.minute ?? 0) }

    var durationMinutes: Int { endMinutes - startMinutes }

    var isValid: Bool { durationMinutes >= Schedule.minimumDurationMinutes }

    func overlaps(_ other: ScheduleWindow) -> Bool {
        startMinutes < other.endMinutes && other.startMinutes < endMinutes
    }

    func contains(minuteOfDay minute: Int) -> Bool {
        minute >= startMinutes && minute < endMinutes
    }

    /// Its own activity, since one `DeviceActivitySchedule` interval cannot express several disjoint spans.
    var activityName: DeviceActivityName {
        DeviceActivityName(id.uuidString)
    }
}

/// Recurring windows in which a profile is blocked or allowed. `weekdays` follows `Calendar`: 1 = Sunday ... 7 = Saturday, and means the day a window starts on.
struct Schedule: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var mode: ScheduleMode
    var weekdays: Set<Int>
    var windows: [ScheduleWindow]
    var budgetMinutes: Int?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        mode: ScheduleMode,
        weekdays: Set<Int>,
        windows: [ScheduleWindow],
        budgetMinutes: Int? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.weekdays = weekdays
        self.windows = windows
        self.budgetMinutes = budgetMinutes
        self.isEnabled = isEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, mode, weekdays, windows, budgetMinutes, isEnabled
    }

    private enum InlineWindowKeys: String, CodingKey {
        case startTime, endTime
    }

    // Schedules saved when a schedule held one window inline carry startTime/endTime instead of a list.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        mode = try container.decode(ScheduleMode.self, forKey: .mode)
        weekdays = try container.decode(Set<Int>.self, forKey: .weekdays)
        budgetMinutes = try container.decodeIfPresent(Int.self, forKey: .budgetMinutes)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)

        if let windows = try container.decodeIfPresent([ScheduleWindow].self, forKey: .windows) {
            self.windows = windows
        } else {
            let inline = try decoder.container(keyedBy: InlineWindowKeys.self)
            windows = [
                ScheduleWindow(
                    startTime: try inline.decode(DateComponents.self, forKey: .startTime),
                    endTime: try inline.decode(DateComponents.self, forKey: .endTime)
                )
            ]
        }
    }

    /// Total time the windows cover in a day.
    var durationMinutes: Int {
        windows.reduce(0) { $0 + $1.durationMinutes }
    }

    /// The shortest window DeviceActivityCenter accepts.
    static let minimumDurationMinutes = 15

    var isValid: Bool {
        !weekdays.isEmpty && !windows.isEmpty && windows.allSatisfy(\.isValid) && !hasOverlappingWindows
    }

    var hasOverlappingWindows: Bool {
        let sorted = sortedWindows
        return zip(sorted, sorted.dropFirst()).contains { $0.overlaps($1) }
    }

    var sortedWindows: [ScheduleWindow] {
        windows.sorted { $0.startMinutes < $1.startMinutes }
    }

    // MARK: - Activity and store identity

    /// One store per schedule, so its shield composes with every other store rather than overwriting it: the system combines settings from separate stores.
    var storeName: ManagedSettingsStore.Name {
        ManagedSettingsStore.Name(id.uuidString)
    }

    /// One all-day activity carries the daily limit in both modes: usage only accrues while the profile is unshielded, which is the span each mode's limit caps.
    var budgetActivityName: DeviceActivityName {
        DeviceActivityName("\(id.uuidString)-budget")
    }

    var budgetEventName: DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("\(id.uuidString)-budget")
    }

    // MARK: - Scheduling logic (shared by ScheduleManager and the monitor extension)

    func isActiveToday(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        weekdays.contains(calendar.component(.weekday, from: referenceDate))
    }

    func isWithinWindow(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        let now = calendar.dateComponents([.hour, .minute], from: referenceDate)
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        return windows.contains { $0.contains(minuteOfDay: nowMinutes) }
    }

    /// Whether a window is open right now: today is a scheduled day, and now falls inside one of the windows.
    func isUsable(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        isActiveToday(referenceDate: referenceDate, calendar: calendar)
            && isWithinWindow(referenceDate: referenceDate, calendar: calendar)
    }

    /// Blocked right now, ignoring `isEnabled`, the daily limit, and any suspension: `.block` blocks during the windows, `.allow` blocks everywhere else.
    func wantsBlock(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        let usable = isUsable(referenceDate: referenceDate, calendar: calendar)
        return mode == .block ? usable : !usable
    }

    /// `wantsBlock()`, plus staying blocked for the rest of today once the limit is spent, which a window boundary would otherwise clear.
    func effectiveWantsBlock(referenceDate: Date = Date(), calendar: Calendar = .current) -> Bool {
        if wantsBlock(referenceDate: referenceDate, calendar: calendar) { return true }
        guard isActiveToday(referenceDate: referenceDate, calendar: calendar) else { return false }
        return SharedStore.isBudgetSpent(for: id)
    }

    /// The next moment a window opens or closes, respecting `weekdays`. Display only: pure window math, with no account of the daily limit or a suspension.
    func nextTransition(referenceDate: Date = Date(), calendar: Calendar = .current) -> Date? {
        var earliest: Date?
        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: referenceDate) else { continue }
            guard weekdays.contains(calendar.component(.weekday, from: day)) else { continue }

            for time in windows.flatMap({ [$0.startTime, $0.endTime] }) {
                guard let candidate = calendar.date(
                    bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day
                ), candidate > referenceDate else { continue }
                if earliest == nil || candidate < earliest! {
                    earliest = candidate
                }
            }
        }
        return earliest
    }
}

extension Schedule {
    /// Every input `effectiveWantsBlock()` reads, in one line, so a shield that is on
    /// can be traced to the value that put it there.
    func decisionSummary(referenceDate: Date = Date(), calendar: Calendar = .current) -> String {
        let windowList = sortedWindows.map {
            String(
                format: "%02d:%02d-%02d:%02d",
                $0.startTime.hour ?? 0, $0.startTime.minute ?? 0, $0.endTime.hour ?? 0, $0.endTime.minute ?? 0
            )
        }.joined(separator: ",")
        return "schedule '\(name)' [\(id.uuidString.prefix(8))] mode=\(mode.rawValue)"
            + " enabled=\(isEnabled) valid=\(isValid) weekdays=\(weekdays.sorted()) windows=\(windowList)"
            + " today=\(isActiveToday(referenceDate: referenceDate, calendar: calendar))"
            + " inWindow=\(isWithinWindow(referenceDate: referenceDate, calendar: calendar))"
            + " budgetMinutes=\(budgetMinutes.map(String.init) ?? "none")"
            + " budgetSpent=\(SharedStore.isBudgetSpent(for: id))"
            + " wantsBlock=\(wantsBlock(referenceDate: referenceDate, calendar: calendar))"
            + " effectiveWantsBlock=\(effectiveWantsBlock(referenceDate: referenceDate, calendar: calendar))"
    }
}

