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
        var resumesAt: Date
        var detail: String
    }
}
