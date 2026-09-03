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

        if profile.restrictWebToAllowlist {
            // webDomainTokens means the opposite thing here: not what's blocked, but
            // the only web content that's still allowed. The per-domain shield is
            // redundant under an allowlist, so it's cleared rather than layered.
            store.shield.webDomains = nil
            let allowed = Set(profile.webDomainTokens.map { WebDomain(token: $0) })
            store.webContent.blockedByFilter = allowed.isEmpty ? .all() : .all(except: allowed)
        } else {
            store.shield.webDomains = profile.webDomainTokens.isEmpty ? nil : profile.webDomainTokens
            store.webContent.blockedByFilter = WebContentSettings.FilterPolicy.none
        }
    }

    static func clear(_ store: ManagedSettingsStore) {
        store.shield.applications = nil
        store.shield.applicationCategories = ShieldSettings.ActivityCategoryPolicy.none
        store.shield.webDomains = nil
        store.webContent.blockedByFilter = WebContentSettings.FilterPolicy.none
    }
}
