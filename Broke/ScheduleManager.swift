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
            startMonitoring(schedule)
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
    }

    private static func startMonitoring(_ schedule: Schedule) {
        let activitySchedule = DeviceActivitySchedule(
            intervalStart: schedule.startTime,
            intervalEnd: schedule.endTime,
            repeats: true
        )

        do {
            try center.startMonitoring(schedule.activityName, during: activitySchedule)
        } catch {
            NSLog("Broke: failed to start monitoring schedule '\(schedule.name)': \(error)")
        }
    }
}
