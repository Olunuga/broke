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
        BrokeLog.log("sync start: profiles=\(profiles.count) manualBlocking=\(SharedStore.isManuallyBlocking) suspended=\(SharedStore.isSuspended) suspendedUntil=\(BrokeLog.timestamp(SharedStore.suspendedUntil))")
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
            let shouldBlock = schedule.isEnabled && schedule.isValid && !SharedStore.isSuspended && schedule.effectiveWantsBlock()

            if shouldBlock, let profile = profileBySchedule[schedule.id] {
                BrokeLog.log("sync applies shield: \(schedule.decisionSummary()) profile='\(profile.name)' apps=\(profile.appTokens.count) categories=\(profile.categoryTokens.count) web=\(profile.webDomainTokens.count)")
                ShieldWriter.apply(profile, to: store)
            } else {
                BrokeLog.log("sync clears shield: \(schedule.decisionSummary())")
                ShieldWriter.clear(store)
            }
        }

        for removedId in previousIds.subtracting(currentIds) {
            BrokeLog.log("sync clears store of deleted schedule [\(removedId.uuidString.prefix(8))]")
            ShieldWriter.clear(ManagedSettingsStore(named: .init(removedId.uuidString)))
        }

        SharedStore.setKnownScheduleIds(currentIds)

        // `stopMonitoring()` above clears every activity, including a pending wake-up
        // from an in-progress suspension. Re-register it so any edit made during a
        // suspension doesn't silently cancel the automatic re-block.
        if SharedStore.isSuspended, let suspendedUntil = SharedStore.suspendedUntil {
            scheduleWakeUp(at: suspendedUntil)
        }

        HardeningManager.refresh()
        logStateSnapshot(profiles: profiles)
    }

    /// What every shield source holds right now, next to the schedule state that
    /// explains it.
    static func stateSnapshotLines(profiles: [Profile]) -> [String] {
        let now = Date()
        var lines = [
            "now=\(BrokeLog.timestamp(now)) weekday=\(Calendar.current.component(.weekday, from: now)) manualBlocking=\(SharedStore.isManuallyBlocking) suspended=\(SharedStore.isSuspended) suspendedUntil=\(BrokeLog.timestamp(SharedStore.suspendedUntil)) emergencyUnblocksLeft=\(SharedStore.remainingEmergencyUnblocks) profileEditUnlocked=\(SharedStore.isProfileEditingUnlocked)",
            "manual store: \(BrokeLog.describe(SharedStore.managedSettingsStore))",
        ]

        for profile in profiles {
            for schedule in profile.schedules {
                let store = ManagedSettingsStore(named: schedule.storeName)
                lines.append("profile='\(profile.name)' \(schedule.decisionSummary(referenceDate: now)) store: \(BrokeLog.describe(store))")
            }
        }
        return lines
    }

    static func logStateSnapshot(profiles: [Profile]) {
        for line in stateSnapshotLines(profiles: profiles) {
            BrokeLog.log("snapshot \(line)")
        }
    }

    /// Suspends every schedule's block for `duration`, effective immediately, and
    /// arranges for it to resume automatically when the suspension ends.
    static func suspendActiveSchedules(for duration: TimeInterval, profiles: [Profile]) {
        BrokeLog.log("suspending schedules for \(Int(duration / 60)) minutes")
        SharedStore.beginSuspension(until: Date().addingTimeInterval(duration))
        sync(profiles: profiles)
    }

    /// Spends one of the month's emergency unblocks, suspending without a tag scan.
    /// Does nothing once the month's allowance is gone.
    @discardableResult
    static func useEmergencyUnblock(profiles: [Profile]) -> Bool {
        guard SharedStore.remainingEmergencyUnblocks > 0 else {
            BrokeLog.log("emergency unblock refused: none left this month")
            return false
        }
        BrokeLog.log("emergency unblock used: \(SharedStore.remainingEmergencyUnblocks - 1) left this month")
        SharedStore.recordEmergencyUnblock()
        suspendActiveSchedules(for: SharedStore.emergencyUnblockDuration, profiles: profiles)
        return true
    }

    private static func startMonitoring(_ schedule: Schedule, profile: Profile) {
        let activitySchedule = DeviceActivitySchedule(
            intervalStart: schedule.startTime,
            intervalEnd: schedule.endTime,
            repeats: true
        )

        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        if schedule.mode == .allow, let budgetMinutes = schedule.budgetMinutes, budgetMinutes > 0 {
            events[schedule.budgetEventName] = budgetEvent(minutes: budgetMinutes, profile: profile)
        }

        do {
            try center.startMonitoring(schedule.activityName, during: activitySchedule, events: events)
            BrokeLog.log("monitoring registered: \(schedule.decisionSummary()) events=\(events.count)")
        } catch {
            BrokeLog.log("monitoring FAILED for schedule '\(schedule.name)': \(error)")
        }

        if schedule.mode == .block, let budgetMinutes = schedule.budgetMinutes, budgetMinutes > 0 {
            startOutsideWindowMonitoring(schedule, profile: profile, budgetMinutes: budgetMinutes)
        }
    }

    /// `.block`'s outside-window budget tracks the whole day, every day this schedule
    /// runs on, rather than reusing the window's own activity — see `Schedule
    /// .outsideWindowActivityName`. `DeviceActivitySchedule` has no weekday parameter,
    /// so this registers daily regardless of `weekdays`; the extension checks
    /// `isActiveToday()` before treating a threshold hit as real.
    private static func startOutsideWindowMonitoring(_ schedule: Schedule, profile: Profile, budgetMinutes: Int) {
        let allDay = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let events = [schedule.outsideWindowEventName: budgetEvent(minutes: budgetMinutes, profile: profile)]

        do {
            try center.startMonitoring(schedule.outsideWindowActivityName, during: allDay, events: events)
            BrokeLog.log("outside-window monitoring registered for '\(schedule.name)' budget=\(budgetMinutes)min")
        } catch {
            BrokeLog.log("outside-window monitoring FAILED for '\(schedule.name)': \(error)")
        }
    }

    /// `includesPastActivity` needs iOS 17.4+; without it, re-registering mid-window
    /// (any schedule edit does, via `stopMonitoring`) resets the budget's accumulated
    /// usage on older OS versions.
    private static func budgetEvent(minutes: Int, profile: Profile) -> DeviceActivityEvent {
        let threshold = DateComponents(minute: minutes)
        if #available(iOS 17.4, *) {
            return DeviceActivityEvent(
                applications: profile.appTokens,
                categories: profile.categoryTokens,
                webDomains: profile.webDomainTokens,
                threshold: threshold,
                includesPastActivity: true
            )
        } else {
            return DeviceActivityEvent(
                applications: profile.appTokens,
                categories: profile.categoryTokens,
                webDomains: profile.webDomainTokens,
                threshold: threshold
            )
        }
    }

    /// A one-shot `DeviceActivitySchedule` from now until `date`, `repeats: false`, so
    /// its `intervalDidEnd` fires exactly once, at the suspension's end.
    ///
    /// Minute precision, not second: `DeviceActivitySchedule`'s documented pattern is
    /// built around hour/minute, and second-level components risked a silent
    /// `invalidDateComponents` failure with no way to observe it from the UI.
    private static func scheduleWakeUp(at date: Date) {
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]

        // DeviceActivityCenter rejects any interval under 15 minutes
        // (intervalTooShort), which a short suspension would otherwise hit — making
        // `startMonitoring` throw, silently, with nothing left to fire the
        // auto-reblock. `intervalEnd` stays exactly at the real suspension deadline;
        // only `intervalStart` moves back far enough to satisfy the minimum.
        let minimumSpan: TimeInterval = 15 * 60
        let now = Date()
        let effectiveStart = min(now, date.addingTimeInterval(-minimumSpan))

        let start = calendar.dateComponents(components, from: effectiveStart)
        // Round the end up a minute so truncating seconds can't put it before `start`.
        let end = calendar.dateComponents(components, from: date.addingTimeInterval(60))
        let wakeSchedule = DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: false)

        do {
            try center.startMonitoring(SharedStore.resumeCheckActivityName, during: wakeSchedule)
            BrokeLog.log("resume check registered for \(BrokeLog.timestamp(date))")
        } catch {
            BrokeLog.log("resume check FAILED for \(BrokeLog.timestamp(date)): \(error)")
        }
    }
}
