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
        BrokeLog.log("intervalDidStart: activity=\(activity.rawValue)")
        guard activity != SharedStore.resumeCheckActivityName else { return }

        if let (profile, schedule) = SharedStore.schedule(forOutsideWindowActivity: activity) {
            // No explicit flag reset here. This fires on every re-registration, not
            // only at midnight — `ScheduleManager.sync` stops and restarts monitoring
            // on every launch and resume, and re-registering an activity whose
            // interval covers now starts it immediately. Clearing the flag here wiped
            // an already-spent budget each time the app opened. The flag is
            // date-stamped and expires on its own at midnight instead.
            apply(schedule, profile: profile)
        } else {
            applyState(for: activity)
        }
        HardeningManager.refresh()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        BrokeLog.log("intervalDidEnd: activity=\(activity.rawValue)")
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
        BrokeLog.log("eventDidReachThreshold: event=\(event.rawValue) activity=\(activity.rawValue) suspended=\(SharedStore.isSuspended)")

        if let (profile, schedule) = SharedStore.schedule(forOutsideWindowActivity: activity),
           event == schedule.outsideWindowEventName {
            guard !SharedStore.isSuspended else { return }
            BrokeLog.log("outside-window budget spent for '\(schedule.name)', enforcing today=\(schedule.isActiveToday())")
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
            BrokeLog.log("no schedule matches activity=\(activity.rawValue), nothing applied")
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
            BrokeLog.log("extension clears shield: \(schedule.decisionSummary()) suspended=\(SharedStore.isSuspended)")
            ShieldWriter.clear(store)
            return
        }

        BrokeLog.log("extension applies shield: \(schedule.decisionSummary()) profile='\(profile.name)' apps=\(profile.appTokens.count)")
        ShieldWriter.apply(profile, to: store)
    }
}
