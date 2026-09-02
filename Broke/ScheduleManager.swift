//
//  ScheduleManager.swift
//  Broke
//
//  Registers each profile's schedules with DeviceActivityCenter and keeps every
//  schedule's own ManagedSettingsStore in sync with its resting (non-boundary) state.
//

import Foundation
import DeviceActivity
import ManagedSettings

enum ScheduleManager {
    private static let center = DeviceActivityCenter()

    /// Reconciles DeviceActivityCenter's registered activities, and every schedule's
    /// shield state, with the current set of profiles. Call after any schedule add,
    /// edit, delete, or enable/disable, and once at app launch.
    static func sync(profiles: [Profile]) {
        center.stopMonitoring()

        let allSchedules = profiles.flatMap { $0.schedules }
        let currentIds = Set(allSchedules.map { $0.id })
        let previousIds = SharedStore.knownScheduleIds()

        let profileBySchedule = Dictionary(
            uniqueKeysWithValues: profiles.flatMap { profile in profile.schedules.map { ($0.id, profile) } }
        )

        for schedule in allSchedules where schedule.isEnabled && schedule.isValid {
            if let profile = profileBySchedule[schedule.id] {
                startMonitoring(schedule, profile: profile)
            }
        }

        for schedule in allSchedules {
            let store = ManagedSettingsStore(named: schedule.storeName)
            let shouldBlock = schedule.isEnabled && schedule.isValid && !SharedStore.isSuspended && schedule.wantsBlock()

            if shouldBlock, let profile = profileBySchedule[schedule.id] {
                ShieldWriter.apply(profile, to: store)
            } else {
                ShieldWriter.clear(store)
            }
        }

        for removedId in previousIds.subtracting(currentIds) {
            ShieldWriter.clear(ManagedSettingsStore(named: .init(removedId.uuidString)))
        }

        SharedStore.setKnownScheduleIds(currentIds)

        // `stopMonitoring()` above clears every activity, including a pending wake-up
        // from an in-progress suspension. Re-register it so any edit made during a
        // suspension doesn't silently cancel the automatic re-block.
        if SharedStore.isSuspended, let suspendedUntil = SharedStore.suspendedUntil {
            scheduleWakeUp(at: suspendedUntil)
        }
    }

    /// Suspends every schedule's block for `duration`, effective immediately, and
    /// arranges for it to resume automatically when the suspension ends.
    static func suspendActiveSchedules(for duration: TimeInterval, profiles: [Profile]) {
        SharedStore.suspendedUntil = Date().addingTimeInterval(duration)
        sync(profiles: profiles)
    }

    private static func startMonitoring(_ schedule: Schedule, profile: Profile) {
        let activitySchedule = DeviceActivitySchedule(
            intervalStart: schedule.startTime,
            intervalEnd: schedule.endTime,
            repeats: true
        )

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        // `.block`'s budget caps usage outside the blocked window, which this
        // activity's interval doesn't cover — not yet designed, see PLAN.md.
        if schedule.mode == .allow, let budgetMinutes = schedule.budgetMinutes, budgetMinutes > 0 {
            let threshold = DateComponents(minute: budgetMinutes)
            // `includesPastActivity` needs iOS 17.4+; without it, re-registering
            // mid-window (any schedule edit does, via stopMonitoring) resets the
            // budget's accumulated usage on older OS versions.
            if #available(iOS 17.4, *) {
                events[schedule.budgetEventName] = DeviceActivityEvent(
                    applications: profile.appTokens,
                    categories: profile.categoryTokens,
                    webDomains: profile.webDomainTokens,
                    threshold: threshold,
                    includesPastActivity: true
                )
            } else {
                events[schedule.budgetEventName] = DeviceActivityEvent(
                    applications: profile.appTokens,
                    categories: profile.categoryTokens,
                    webDomains: profile.webDomainTokens,
                    threshold: threshold
                )
            }
        }

        do {
            try center.startMonitoring(schedule.activityName, during: activitySchedule, events: events)
        } catch {
            NSLog("Broke: failed to start monitoring schedule '\(schedule.name)': \(error)")
        }
    }

    /// A one-shot `DeviceActivitySchedule` from now until `date`, `repeats: false`, so
    /// its `intervalDidEnd` fires exactly once, at the suspension's end.
    private static func scheduleWakeUp(at date: Date) {
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let start = calendar.dateComponents(components, from: Date())
        let end = calendar.dateComponents(components, from: date)
        let wakeSchedule = DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false)

        do {
            try center.startMonitoring(SharedStore.resumeCheckActivityName, during: wakeSchedule)
        } catch {
            NSLog("Broke: failed to schedule resume check: \(error)")
        }
    }
}
