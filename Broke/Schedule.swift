//
//  Schedule.swift
//  Broke
//

import Foundation

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
}
