//
//  ShieldWriter.swift
//  Broke
//
//  Shared by the app (manual toggle, resting schedule state) and the
//  DeviceActivityMonitor extension (schedule transitions).
//

import ManagedSettings

/// The four settings a shield source writes. `ManagedSettingsStore` has no readable state, so tests substitute their own target.
protocol ShieldTarget: AnyObject {
    var shieldedApplications: Set<ApplicationToken>? { get set }
    var shieldedCategories: ShieldSettings.ActivityCategoryPolicy<Application>? { get set }
    var shieldedWebDomains: Set<WebDomainToken>? { get set }
    var blockedByFilter: WebContentSettings.FilterPolicy? { get set }
}

extension ManagedSettingsStore: ShieldTarget {
    var shieldedApplications: Set<ApplicationToken>? {
        get { shield.applications }
        set { shield.applications = newValue }
    }

    var shieldedCategories: ShieldSettings.ActivityCategoryPolicy<Application>? {
        get { shield.applicationCategories }
        set { shield.applicationCategories = newValue }
    }

    var shieldedWebDomains: Set<WebDomainToken>? {
        get { shield.webDomains }
        set { shield.webDomains = newValue }
    }

    var blockedByFilter: WebContentSettings.FilterPolicy? {
        get { webContent.blockedByFilter }
        set { webContent.blockedByFilter = newValue }
    }
}

enum ShieldWriter {
    static func apply(_ profile: Profile, to store: ShieldTarget) {
        store.shieldedApplications = profile.appTokens.isEmpty ? nil : profile.appTokens
        store.shieldedCategories = profile.categoryTokens.isEmpty
            ? ShieldSettings.ActivityCategoryPolicy.none
            : .specific(profile.categoryTokens)

        if profile.restrictWebToAllowlist {
            // webDomainTokens means the opposite thing here: not what's blocked, but
            // the only web content that's still allowed. The per-domain shield is
            // redundant under an allowlist, so it's cleared rather than layered.
            store.shieldedWebDomains = nil
            let allowed = Set(profile.webDomainTokens.map { WebDomain(token: $0) })
            store.blockedByFilter = allowed.isEmpty ? .all() : .all(except: allowed)
        } else {
            store.shieldedWebDomains = profile.webDomainTokens.isEmpty ? nil : profile.webDomainTokens
            store.blockedByFilter = WebContentSettings.FilterPolicy.none
        }
    }

    static func clear(_ store: ShieldTarget) {
        store.shieldedApplications = nil
        store.shieldedCategories = ShieldSettings.ActivityCategoryPolicy.none
        store.shieldedWebDomains = nil
        store.blockedByFilter = WebContentSettings.FilterPolicy.none
    }
}
