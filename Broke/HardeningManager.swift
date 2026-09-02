//
//  HardeningManager.swift
//  Broke
//
//  Device-level restrictions that apply while anything is blocking, to close ways
//  around a shield the shield itself doesn't cover. Shared by the app and the
//  DeviceActivityMonitor extension, since either can be the one whose action changes
//  whether anything is blocking.
//

import ManagedSettings

enum HardeningManager {
    private static let store = ManagedSettingsStore(named: .init("broke-hardening"))

    /// Recomputes from `SharedStore.isAnythingBlocking` and applies or clears every
    /// restriction accordingly. Call whenever blocking state could have changed: after
    /// the manual toggle, after `ScheduleManager.sync`, and after the extension applies
    /// or clears a schedule's shield.
    static func refresh() {
        if SharedStore.isAnythingBlocking {
            store.application.denyAppRemoval = true
            store.dateAndTime.requireAutomaticDateAndTime = true
            store.account.lockAccounts = true
            store.passcode.lockPasscode = true
            store.siri.denySiri = true
        } else {
            store.application.denyAppRemoval = nil
            store.dateAndTime.requireAutomaticDateAndTime = nil
            store.account.lockAccounts = nil
            store.passcode.lockPasscode = nil
            store.siri.denySiri = nil
        }
    }
}
