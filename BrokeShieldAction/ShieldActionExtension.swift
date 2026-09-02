//
//  ShieldActionExtension.swift
//  BrokeShieldAction
//

import ManagedSettings

/// Neither `ShieldActionResponse` case can trigger the system's passcode-override
/// prompt — that only happens on the default, unconfigured shield. Once this
/// extension and ShieldConfigurationExtension are both installed, `.close` here is
/// the strongest response available: dismiss the shield UI. It never touches the
/// underlying ManagedSettingsStore, so nothing gets unblocked from inside the shield
/// itself — the Broke tag is the only way through.
class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }
}
