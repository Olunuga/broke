//
//  SharedStore.swift
//  Broke
//
//  Shared state between the main app and the DeviceActivityMonitor extension.
//

import Foundation
import DeviceActivity
import ManagedSettings

enum SharedStore {
    static let appGroupID = "group.com.Brokeest.ios"

    static let defaults: UserDefaults = {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            fatalError("App Group '\(appGroupID)' is not configured. Add it in Signing & Capabilities.")
        }
        return defaults
    }()

    static let managedSettingsStore = ManagedSettingsStore(named: .init("broke"))

    /// One-off activity used to wake the extension when a suspension ends, so the
    /// shield a schedule cleared for an early unblock gets re-applied without waiting
    /// for that schedule's own next start/end boundary.
    static let resumeCheckActivityName = DeviceActivityName("broke-resume-check")

    // MARK: - Keys

    private enum Key {
        static let savedProfiles = "savedProfiles"
        static let currentProfileId = "currentProfileId"
        static let isBlocking = "isBlocking"
        static let suspendedUntil = "suspendedUntil"
        static let didMigrateFromStandardDefaults = "didMigrateFromStandardDefaults"
        static let knownScheduleIds = "knownScheduleIds"
    }

    // MARK: - Profiles

    static func loadProfiles() -> [Profile] {
        guard let data = defaults.data(forKey: Key.savedProfiles),
              let profiles = try? JSONDecoder().decode([Profile].self, from: data) else {
            return []
        }
        return profiles
    }

    static func saveProfiles(_ profiles: [Profile]) {
        guard let encoded = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(encoded, forKey: Key.savedProfiles)
    }

    /// Finds the schedule with `scheduleId` across every profile, along with the
    /// profile that owns it. Used by the extension, which only has a schedule's id
    /// (from `DeviceActivityName`) and needs the profile's tokens to shield.
    static func schedule(withId scheduleId: UUID) -> (profile: Profile, schedule: Schedule)? {
        for profile in loadProfiles() {
            if let schedule = profile.schedules.first(where: { $0.id == scheduleId }) {
                return (profile, schedule)
            }
        }
        return nil
    }

    /// Same lookup, for a schedule's `outsideWindowActivityName` instead of its main
    /// one — that name carries an `"-outside"` suffix `UUID(uuidString:)` can't parse
    /// directly, so the suffix is stripped first.
    static func schedule(forOutsideWindowActivity activity: DeviceActivityName) -> (profile: Profile, schedule: Schedule)? {
        let suffix = "-outside"
        guard activity.rawValue.hasSuffix(suffix) else { return nil }
        let idString = String(activity.rawValue.dropLast(suffix.count))
        guard let id = UUID(uuidString: idString) else { return nil }
        return schedule(withId: id)
    }

    // MARK: - Known schedule ids

    /// Schedule ids seen as of the last `ScheduleManager.sync`. Used to detect
    /// schedules that were deleted since, whose named `ManagedSettingsStore` would
    /// otherwise keep whatever shield state it last had forever.
    static func knownScheduleIds() -> Set<UUID> {
        guard let strings = defaults.array(forKey: Key.knownScheduleIds) as? [String] else { return [] }
        return Set(strings.compactMap(UUID.init))
    }

    static func setKnownScheduleIds(_ ids: Set<UUID>) {
        defaults.set(ids.map { $0.uuidString }, forKey: Key.knownScheduleIds)
    }

    // MARK: - Suspension (NFC early unblock, phase 6)

    static var suspendedUntil: Date? {
        get { defaults.object(forKey: Key.suspendedUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.suspendedUntil) }
    }

    static var isSuspended: Bool {
        guard let suspendedUntil else { return false }
        return Date() < suspendedUntil
    }

    /// Every enabled, valid schedule that wants its profile blocked right now. Empty
    /// means no schedule is currently blocking. Drives the home screen's blocked
    /// state, and the window/budget details it shows, alongside the manual toggle.
    static func activeBlockingSchedules() -> [Schedule] {
        guard !isSuspended else { return [] }
        var schedules: [Schedule] = []
        for profile in loadProfiles() {
            for schedule in profile.schedules where schedule.isEnabled && schedule.isValid {
                if schedule.effectiveWantsBlock() { schedules.append(schedule) }
            }
        }
        return schedules
    }

    // MARK: - Outside-window budget (`.block` mode)

    /// Whether a `.block` schedule's outside-window budget has already been spent
    /// today. Stored as the date it was set rather than a bare flag, and checked
    /// against "is that date today" — self-expiring, rather than depending on the
    /// tracking activity's midnight `intervalDidStart` firing reliably to clear it.
    /// A missed background callback here would otherwise leave a schedule stuck
    /// showing as blocking indefinitely.
    static func isOutsideWindowBudgetExceeded(for scheduleId: UUID) -> Bool {
        guard let date = defaults.object(forKey: "outsideWindowBudgetExceededDate-\(scheduleId.uuidString)") as? Date else {
            return false
        }
        return Calendar.current.isDateInToday(date)
    }

    static func setOutsideWindowBudgetExceeded(_ exceeded: Bool, for scheduleId: UUID) {
        let key = "outsideWindowBudgetExceededDate-\(scheduleId.uuidString)"
        if exceeded {
            defaults.set(Date(), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    static func isAnyScheduleBlocking() -> Bool {
        !activeBlockingSchedules().isEmpty
    }

    static var isManuallyBlocking: Bool {
        defaults.bool(forKey: Key.isBlocking)
    }

    /// Whether anything — the manual toggle or a schedule — is blocking right now.
    /// Drives device-level restrictions in `HardeningManager`, which apply while
    /// something is blocked and lift once nothing is.
    static var isAnythingBlocking: Bool {
        isManuallyBlocking || isAnyScheduleBlocking()
    }

    // MARK: - One-time migration from UserDefaults.standard

    /// Earlier versions stored profiles and blocking state in `UserDefaults.standard`,
    /// which the extension cannot read. Copy them into the App Group once.
    static func migrateFromStandardDefaultsIfNeeded() {
        guard !defaults.bool(forKey: Key.didMigrateFromStandardDefaults) else { return }

        let standard = UserDefaults.standard
        if let profiles = standard.data(forKey: Key.savedProfiles) {
            defaults.set(profiles, forKey: Key.savedProfiles)
        }
        if let currentProfileId = standard.string(forKey: Key.currentProfileId) {
            defaults.set(currentProfileId, forKey: Key.currentProfileId)
        }
        defaults.set(standard.bool(forKey: Key.isBlocking), forKey: Key.isBlocking)

        // Earlier versions shielded through the default (unnamed) store. Clear it so a
        // shield applied before this update doesn't stay stuck there forever.
        ManagedSettingsStore().clearAllSettings()

        defaults.set(true, forKey: Key.didMigrateFromStandardDefaults)
    }
}
