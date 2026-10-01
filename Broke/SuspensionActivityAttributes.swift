//
//  SuspensionActivityAttributes.swift
//  Broke
//
//  Shared by the app, which starts and updates the Live Activity, and the widget
//  extension, which draws it.
//

import ActivityKit
import Foundation

struct SuspensionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The countdown is drawn over this span. A deadline alone gives an open-ended
        /// timer, which counts upwards once it passes.
        var startedAt: Date
        var resumesAt: Date
        var detail: String

        /// The span the countdown is drawn over. Clamped, since a range whose start is after its end cannot be built.
        var countdownRange: ClosedRange<Date> {
            min(startedAt, resumesAt)...resumesAt
        }
    }
}
