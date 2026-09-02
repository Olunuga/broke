//
//  Profile.swift
//  Broke
//

import Foundation
import ManagedSettings

struct Profile: Identifiable, Codable {
    let id: UUID
    var name: String
    var appTokens: Set<ApplicationToken>
    var categoryTokens: Set<ActivityCategoryToken>
    var webDomainTokens: Set<WebDomainToken>
    var schedules: [Schedule]
    var icon: String
    /// When true, `webDomainTokens` is treated as the only web content allowed —
    /// everything else is blocked — instead of the default deny-list meaning (only
    /// those domains are blocked, everything else is allowed).
    var restrictWebToAllowlist: Bool

    var isDefault: Bool {
        name == "Default"
    }

    init(
        name: String,
        appTokens: Set<ApplicationToken>,
        categoryTokens: Set<ActivityCategoryToken>,
        webDomainTokens: Set<WebDomainToken> = [],
        schedules: [Schedule] = [],
        restrictWebToAllowlist: Bool = false,
        icon: String = "bell.slash"
    ) {
        self.id = UUID()
        self.name = name
        self.appTokens = appTokens
        self.categoryTokens = categoryTokens
        self.webDomainTokens = webDomainTokens
        self.schedules = schedules
        self.restrictWebToAllowlist = restrictWebToAllowlist
        self.icon = icon
    }

    // Profiles saved before webDomainTokens/schedules/restrictWebToAllowlist existed
    // have no such keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        appTokens = try container.decode(Set<ApplicationToken>.self, forKey: .appTokens)
        categoryTokens = try container.decode(Set<ActivityCategoryToken>.self, forKey: .categoryTokens)
        webDomainTokens = try container.decodeIfPresent(Set<WebDomainToken>.self, forKey: .webDomainTokens) ?? []
        schedules = try container.decodeIfPresent([Schedule].self, forKey: .schedules) ?? []
        restrictWebToAllowlist = try container.decodeIfPresent(Bool.self, forKey: .restrictWebToAllowlist) ?? false
        icon = try container.decode(String.self, forKey: .icon)
    }
}
