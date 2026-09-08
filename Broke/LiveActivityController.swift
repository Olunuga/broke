//
//  LiveActivityController.swift
//  Broke
//
//  Reports a running suspension on the Lock Screen and in the Dynamic Island.
//

import ActivityKit
import Foundation

/// A suspension is what this shows, not a block: it is short enough to fit inside the
/// system's activity lifetime, and it always starts in the foreground from a tag scan
/// or an emergency unblock, which is the only place `Activity.request` is allowed.
enum LiveActivityController {
    private static var lastState: SuspensionActivityAttributes.ContentState?

    static func refresh(profiles: [Profile]) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard let resumesAt = SharedStore.suspendedUntil, Date() < resumesAt else {
            end()
            return
        }

        let state = SuspensionActivityAttributes.ContentState(
            resumesAt: resumesAt,
            detail: detail(for: profiles)
        )
        guard state != lastState else { return }
        lastState = state

        // The activity outlives the app, which cannot end it from the background, so
        // the stale date marks it spent at the moment blocking resumes.
        let content = ActivityContent(state: state, staleDate: resumesAt)
        if let activity = Activity<SuspensionActivityAttributes>.activities.first {
            Task { await activity.update(content) }
            return
        }

        do {
            _ = try Activity.request(attributes: SuspensionActivityAttributes(), content: content, pushType: nil)
            BrokeLog.log("live activity started, blocking resumes at \(BrokeLog.timestamp(resumesAt))")
        } catch {
            BrokeLog.log("live activity FAILED to start: \(error)")
        }
    }

    static func end() {
        guard lastState != nil || !Activity<SuspensionActivityAttributes>.activities.isEmpty else { return }
        lastState = nil
        for activity in Activity<SuspensionActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Names what resumes, which the suspension itself does not record.
    private static func detail(for profiles: [Profile]) -> String {
        let names = profiles
            .flatMap { $0.schedules }
            .filter { $0.isEnabled && $0.isValid && $0.effectiveWantsBlock() }
            .map { $0.name }
        return names.isEmpty ? "Scan your tag to resume" : names.joined(separator: " · ")
    }
}
