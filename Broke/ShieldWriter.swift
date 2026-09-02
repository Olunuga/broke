//
//  ShieldWriter.swift
//  Broke
//
//  Shared by the app (manual toggle, resting schedule state) and the
//  DeviceActivityMonitor extension (schedule transitions).
//

import ManagedSettings

enum ShieldWriter {
    static func apply(_ profile: Profile, to store: ManagedSettingsStore) {
        store.shield.applications = profile.appTokens.isEmpty ? nil : profile.appTokens
        store.shield.applicationCategories = profile.categoryTokens.isEmpty
            ? ShieldSettings.ActivityCategoryPolicy.none
            : .specific(profile.categoryTokens)
        store.shield.webDomains = profile.webDomainTokens.isEmpty ? nil : profile.webDomainTokens
    }

    static func clear(_ store: ManagedSettingsStore) {
        store.shield.applications = nil
        store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.none
        store.shield.webDomains = nil
    }
}
