//
//  SharedStore.swift
//  Broke
//
//  Shared state between the main app and the DeviceActivityMonitor extension.
//

import Foundation
import DeviceActivity
import ManagedSettings
import os

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
        static let emergencyUnblocksUsedDate = "emergencyUnblocksUsedDateKey"
        static let emergencyUnblocksUsedCount = "emergencyUnblocksUsedCountKey"
        static let profileEditUnlockedUntil = "profileEditUnlockedUntil"
        static let recentLogLines = "recentLogLines"
    }

    // MARK: - Suspension durations

    static let suspensionDuration: TimeInterval = 60 * 60
    static let emergencyUnblockDuration: TimeInterval = 15 * 60
    static let maximumEmergencyUnblocks = 5
    static let profileEditAccessDuration: TimeInterval = 10 * 60

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
        defaults.object(forKey: Key.suspendedUntil) as? Date
    }

    static func beginSuspension(until date: Date) {
        defaults.set(date, forKey: Key.suspendedUntil)
    }

    static func clearSuspension() {
        defaults.removeObject(forKey: Key.suspendedUntil)
    }

    /// Emergency unblocks taken this calendar month. One stored date plus a count is
    /// enough: a stamp from an earlier month reads as zero used, and the next unblock
    /// restamps it. Derived from the stored date rather than reset by a callback, so
    /// nothing has to fire at the month boundary for the allowance to refill.
    static var emergencyUnblocksUsedThisMonth: Int {
        guard let date = defaults.object(forKey: Key.emergencyUnblocksUsedDate) as? Date,
              Calendar.current.isDate(date, equalTo: Date(), toGranularity: .month) else {
            return 0
        }
        return defaults.integer(forKey: Key.emergencyUnblocksUsedCount)
    }

    static var remainingEmergencyUnblocks: Int {
        max(0, maximumEmergencyUnblocks - emergencyUnblocksUsedThisMonth)
    }

    static func recordEmergencyUnblock() {
        let used = emergencyUnblocksUsedThisMonth
        defaults.set(Date(), forKey: Key.emergencyUnblocksUsedDate)
        defaults.set(used + 1, forKey: Key.emergencyUnblocksUsedCount)
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

    // MARK: - Profile editing access

    /// Editing a profile changes what every block covers, so a tag scan grants it for
    /// `profileEditAccessDuration` and nothing else does.
    static func grantProfileEditAccess() {
        defaults.set(Date().addingTimeInterval(profileEditAccessDuration), forKey: Key.profileEditUnlockedUntil)
    }

    static func revokeProfileEditAccess() {
        defaults.removeObject(forKey: Key.profileEditUnlockedUntil)
    }

    static var isProfileEditingUnlocked: Bool {
        guard !isAnythingBlocking,
              let unlockedUntil = defaults.object(forKey: Key.profileEditUnlockedUntil) as? Date else { return false }
        return Date() < unlockedUntil
    }

    // MARK: - Log lines

    /// The app cannot read the extension's os_log output, so every line is also kept
    /// here, in the App Group both processes share.
    static let maximumStoredLogLines = 400

    static var recentLogLines: [String] {
        defaults.stringArray(forKey: Key.recentLogLines) ?? []
    }

    static func appendLogLine(_ line: String) {
        var lines = recentLogLines
        lines.append(line)
        if lines.count > maximumStoredLogLines {
            lines.removeFirst(lines.count - maximumStoredLogLines)
        }
        defaults.set(lines, forKey: Key.recentLogLines)
    }

    static func clearLogLines() {
        defaults.removeObject(forKey: Key.recentLogLines)
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

/// One log channel for the app and the extension, so a shield decision made in the
/// background reads in the same stream as the app's own.
/// Stream it with: log stream --predicate 'subsystem == "com.Brokeest.ios"'
enum BrokeLog {
    private static let logger = Logger(subsystem: "com.Brokeest.ios", category: "broke")

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let lineFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter
    }()

    // Every value is marked public: this is the user's own device state, and it reads
    // as <private> in Console otherwise.
    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        SharedStore.appendLogLine("\(lineFormatter.string(from: Date())) \(message)")
    }

    static func timestamp(_ date: Date?) -> String {
        guard let date else { return "none" }
        return timestampFormatter.string(from: date)
    }

    /// What a store currently shields, by count rather than by token, so a line stays
    /// readable and carries no token payload.
    static func describe(_ store: ManagedSettingsStore) -> String {
        let apps = store.shield.applications?.count ?? 0
        let webDomains = store.shield.webDomains?.count ?? 0
        return "apps=\(apps) categories=\(categorySummary(store.shield.applicationCategories)) web=\(webDomains) filter=\(filterSummary(store.webContent.blockedByFilter))"
    }

    private static func categorySummary<T>(_ policy: ShieldSettings.ActivityCategoryPolicy<T>?) -> String {
        guard let policy else { return "nil" }
        if case .none = policy { return "none" }
        return "shielding"
    }

    private static func filterSummary(_ policy: WebContentSettings.FilterPolicy?) -> String {
        guard let policy else { return "nil" }
        if case .none = policy { return "none" }
        return "restricting"
    }
}

