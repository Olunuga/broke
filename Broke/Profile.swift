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

    var isDefault: Bool {
        name == "Default"
    }

    init(
        name: String,
        appTokens: Set<ApplicationToken>,
        categoryTokens: Set<ActivityCategoryToken>,
        webDomainTokens: Set<WebDomainToken> = [],
        schedules: [Schedule] = [],
        icon: String = "bell.slash"
    ) {
        self.id = UUID()
        self.name = name
        self.appTokens = appTokens
        self.categoryTokens = categoryTokens
        self.webDomainTokens = webDomainTokens
        self.schedules = schedules
        self.icon = icon
    }

    // Profiles saved before webDomainTokens/schedules existed have no such keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        appTokens = try container.decode(Set<ApplicationToken>.self, forKey: .appTokens)
        categoryTokens = try container.decode(Set<ActivityCategoryToken>.self, forKey: .categoryTokens)
        webDomainTokens = try container.decodeIfPresent(Set<WebDomainToken>.self, forKey: .webDomainTokens) ?? []
        schedules = try container.decodeIfPresent([Schedule].self, forKey: .schedules) ?? []
        icon = try container.decode(String.self, forKey: .icon)
    }
}
