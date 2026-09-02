//
//  SharedStore.swift
//  Broke
//
//  Shared state between the main app and the DeviceActivityMonitor extension.
//

import Foundation
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

    // MARK: - Keys

    private enum Key {
        static let savedProfiles = "savedProfiles"
        static let currentProfileId = "currentProfileId"
        static let isBlocking = "isBlocking"
        static let suspendedUntil = "suspendedUntil"
        static let didMigrateFromStandardDefaults = "didMigrateFromStandardDefaults"
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
