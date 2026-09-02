//
//  DeviceActivityMonitorExtension.swift
//  BrokeMonitor
//

import Foundation
import DeviceActivity
import ManagedSettings

class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity != SharedStore.resumeCheckActivityName else { return }
        applyState(for: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == SharedStore.resumeCheckActivityName {
            // A suspension just ended. Nothing else fires exactly at this moment, so
            // every schedule is re-evaluated here rather than just the one that was
            // suspended.
            reapplyAllKnownSchedules()
        } else {
            applyState(for: activity)
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        // Daily budgets land in phase 5.
    }

    /// Neither callback says which edge fired, and a schedule only runs on some
    /// weekdays, so state is always recomputed from scratch here rather than assumed
    /// from which callback ran.
    private func applyState(for activity: DeviceActivityName) {
        guard let scheduleId = UUID(uuidString: activity.rawValue),
              let (profile, schedule) = SharedStore.schedule(withId: scheduleId) else {
            return
        }
        apply(schedule, profile: profile)
    }

    private func reapplyAllKnownSchedules() {
        for profile in SharedStore.loadProfiles() {
            for schedule in profile.schedules {
                apply(schedule, profile: profile)
            }
        }
    }

    private func apply(_ schedule: Schedule, profile: Profile) {
        let store = ManagedSettingsStore(named: schedule.storeName)

        guard schedule.isEnabled, !SharedStore.isSuspended, schedule.wantsBlock() else {
            ShieldWriter.clear(store)
            return
        }

        ShieldWriter.apply(profile, to: store)
    }
}
