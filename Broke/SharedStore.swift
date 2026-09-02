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

    /// Whether any enabled, valid schedule wants its profile blocked right now.
    /// Drives the home screen's blocked state alongside the manual toggle.
    static func isAnyScheduleBlocking() -> Bool {
        guard !isSuspended else { return false }
        for profile in loadProfiles() {
            for schedule in profile.schedules where schedule.isEnabled && schedule.isValid {
                if schedule.wantsBlock() { return true }
            }
        }
        return false
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
