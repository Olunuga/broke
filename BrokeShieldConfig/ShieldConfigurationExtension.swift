//
//  ShieldConfigurationExtension.swift
//  BrokeShieldConfig
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        Self.blockedConfiguration
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        Self.blockedConfiguration
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        Self.blockedConfiguration
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        Self.blockedConfiguration
    }

    /// No secondary button — that's where the default shield's built-in "unlock with
    /// Screen Time passcode" option lives. Scanning the Broke tag is the only way
    /// through; the primary button just dismisses (see ShieldActionExtension).
    private static var blockedConfiguration: ShieldConfiguration {
        ShieldConfiguration(
            backgroundColor: .black,
            icon: UIImage(systemName: "hand.raised.slash.fill"),
            title: ShieldConfiguration.Label(text: "Blocked by Broke", color: .white),
            subtitle: ShieldConfiguration.Label(text: "Scan your Broke tag to unblock.", color: .lightGray),
            primaryButtonLabel: ShieldConfiguration.Label(text: "OK", color: .black),
            primaryButtonBackgroundColor: .white
        )
    }
}
