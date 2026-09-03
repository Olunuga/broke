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

        if let (profile, schedule) = SharedStore.schedule(forOutsideWindowActivity: activity) {
            // The outside-window tracker's own threshold counter resets here too —
            // same moment, same daily cycle.
            SharedStore.setOutsideWindowBudgetExceeded(false, for: schedule.id)
            apply(schedule, profile: profile)
        } else {
            applyState(for: activity)
        }
        HardeningManager.refresh()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == SharedStore.resumeCheckActivityName {
            // A suspension just ended. Nothing else fires exactly at this moment, so
            // every schedule is re-evaluated here rather than just the one that was
            // suspended.
            reapplyAllKnownSchedules()
        } else if let (profile, schedule) = SharedStore.schedule(forOutsideWindowActivity: activity) {
            apply(schedule, profile: profile)
        } else {
            applyState(for: activity)
        }
        HardeningManager.refresh()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        if let (profile, schedule) = SharedStore.schedule(forOutsideWindowActivity: activity),
           event == schedule.outsideWindowEventName {
            guard !SharedStore.isSuspended else { return }
            SharedStore.setOutsideWindowBudgetExceeded(true, for: schedule.id)
            // Only enforce if today is actually one of this schedule's days — the
            // tracker runs daily regardless of `weekdays`, since DeviceActivitySchedule
            // has no weekday parameter to filter it by.
            if schedule.isActiveToday() {
                ShieldWriter.apply(profile, to: ManagedSettingsStore(named: schedule.storeName))
            }
            HardeningManager.refresh()
            return
        }

        guard let scheduleId = UUID(uuidString: activity.rawValue),
              let (profile, schedule) = SharedStore.schedule(withId: scheduleId),
              event == schedule.budgetEventName,
              !SharedStore.isSuspended else {
            return
        }

        // Budget spent for the rest of today's window. The threshold resets, and this
        // clears, at the schedule's own next intervalDidStart — no separate reset
        // logic needed.
        ShieldWriter.apply(profile, to: ManagedSettingsStore(named: schedule.storeName))
        HardeningManager.refresh()
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

        guard schedule.isEnabled, !SharedStore.isSuspended, schedule.effectiveWantsBlock() else {
            ShieldWriter.clear(store)
            return
        }

        ShieldWriter.apply(profile, to: store)
    }
}
