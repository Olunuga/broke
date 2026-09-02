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
        applyState(for: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        applyState(for: activity)
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

        let store = ManagedSettingsStore(named: schedule.storeName)

        guard schedule.isEnabled, !SharedStore.isSuspended, schedule.wantsBlock() else {
            ShieldWriter.clear(store)
            return
        }

        ShieldWriter.apply(profile, to: store)
    }
}
