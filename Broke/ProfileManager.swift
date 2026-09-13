//
//  ProfileManager.swift
//  Broke
//
//  Created by Oz Tamir on 22/08/2024.
//

import Foundation
import FamilyControls
import ManagedSettings

class ProfileManager: ObservableObject {
    @Published var profiles: [Profile] = []
    @Published var currentProfileId: UUID?
    
    init() {
        loadProfiles()
        ensureDefaultProfile()
    }
    
    var currentProfile: Profile {
        (profiles.first(where: { $0.id == currentProfileId }) ?? profiles.first(where: { $0.name == "Default" }))!
    }
    
    func loadProfiles() {
        profiles = SharedStore.loadProfiles()
        if profiles.isEmpty {
            let defaultProfile = Profile(name: "Default", appTokens: [], categoryTokens: [], icon: "bell.slash")
            profiles = [defaultProfile]
            currentProfileId = defaultProfile.id
        }

        if let savedProfileId = SharedStore.defaults.string(forKey: "currentProfileId"),
           let uuid = UUID(uuidString: savedProfileId) {
            currentProfileId = uuid
            NSLog("Found currentProfile: \(uuid)")
        } else {
            currentProfileId = profiles.first?.id
            NSLog("No stored ID, using \(currentProfileId?.uuidString ?? "NONE")")
        }
    }

    func saveProfiles() {
        SharedStore.saveProfiles(profiles)
        SharedStore.defaults.set(currentProfileId?.uuidString, forKey: "currentProfileId")
    }
    
    func addProfile(name: String, icon: String = "bell.slash") {
        let newProfile = Profile(name: name, appTokens: [], categoryTokens: [], icon: icon)
        profiles.append(newProfile)
        currentProfileId = newProfile.id
        saveProfiles()
    }
    
    func addProfile(newProfile: Profile) {
        profiles.append(newProfile)
        currentProfileId = newProfile.id
        saveProfiles()
    }
    
    func updateCurrentProfile(appTokens: Set<ApplicationToken>, categoryTokens: Set<ActivityCategoryToken>) {
        if let index = profiles.firstIndex(where: { $0.id == currentProfileId }) {
            profiles[index].appTokens = appTokens
            profiles[index].categoryTokens = categoryTokens
            saveProfiles()
        }
    }
    
    func setCurrentProfile(id: UUID) {
        if profiles.contains(where: { $0.id == id }) {
            currentProfileId = id
            NSLog("New Current Profile: \(id)")
            saveProfiles()
        }
    }
    
    func deleteProfile(withId id: UUID) {
//        guard !profiles.first(where: { $0.id == id })?.isDefault ?? false else {
//            // Don't delete the default profile
//            return
//        }
        
        profiles.removeAll { $0.id == id }
        
        if currentProfileId == id {
            currentProfileId = profiles.first?.id
        }
        
        saveProfiles()
    }

    func deleteAllNonDefaultProfiles() {
        profiles.removeAll { !$0.isDefault }
        
        if !profiles.contains(where: { $0.id == currentProfileId }) {
            currentProfileId = profiles.first?.id
        }
        
        saveProfiles()
    }
    
    func updateCurrentProfile(name: String, iconName: String) {
        if let index = profiles.firstIndex(where: { $0.id == currentProfileId }) {
            profiles[index].name = name
            profiles[index].icon = iconName
            saveProfiles()
        }
    }

    func deleteCurrentProfile() {
        profiles.removeAll { $0.id == currentProfileId }
        if let firstProfile = profiles.first {
            currentProfileId = firstProfile.id
        }
        saveProfiles()
    }
    
    func updateProfile(
        id: UUID,
        name: String? = nil,
        appTokens: Set<ApplicationToken>? = nil,
        categoryTokens: Set<ActivityCategoryToken>? = nil,
        webDomainTokens: Set<WebDomainToken>? = nil,
        restrictWebToAllowlist: Bool? = nil,
        icon: String? = nil
    ) {
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            if let name = name {
                profiles[index].name = name
            }
            if let appTokens = appTokens {
                profiles[index].appTokens = appTokens
            }
            if let categoryTokens = categoryTokens {
                profiles[index].categoryTokens = categoryTokens
            }
            if let webDomainTokens = webDomainTokens {
                profiles[index].webDomainTokens = webDomainTokens
            }
            if let restrictWebToAllowlist = restrictWebToAllowlist {
                profiles[index].restrictWebToAllowlist = restrictWebToAllowlist
            }
            if let icon = icon {
                profiles[index].icon = icon
            }
            
            if currentProfileId == id {
                currentProfileId = profiles[index].id
            }
            
            saveProfiles()
        }
    }

    // MARK: - Import

    /// Appends every profile in `transfer`, leaving the current profile alone.
    @discardableResult
    func importProfiles(from transfer: ProfileTransfer) -> ProfileImportResult {
        let keepSelections = transfer.carriesUsableSelections
        var importedNames: [String] = []

        for item in transfer.profiles {
            let name = uniqueProfileName(from: item.name)
            // A schedule's id names its ManagedSettingsStore and a window's id names its DeviceActivityName, so a reused one would collide.
            let schedules = item.schedules.map { schedule in
                Schedule(
                    id: UUID(),
                    name: schedule.name,
                    mode: schedule.mode,
                    weekdays: schedule.weekdays,
                    windows: schedule.windows.map { ScheduleWindow(startTime: $0.startTime, endTime: $0.endTime) },
                    budgetMinutes: schedule.budgetMinutes,
                    isEnabled: keepSelections && schedule.isEnabled
                )
            }

            profiles.append(
                Profile(
                    name: name,
                    appTokens: keepSelections ? item.appTokens : [],
                    categoryTokens: keepSelections ? item.categoryTokens : [],
                    webDomainTokens: keepSelections ? item.webDomainTokens : [],
                    schedules: schedules,
                    restrictWebToAllowlist: item.restrictWebToAllowlist,
                    icon: item.icon
                )
            )
            importedNames.append(name)
        }

        saveProfiles()
        ScheduleManager.sync(profiles: profiles)
        BrokeLog.log("imported \(importedNames.count) profiles, selections kept=\(keepSelections)")

        return ProfileImportResult(importedNames: importedNames, keptSelections: keepSelections)
    }

    private func uniqueProfileName(from name: String) -> String {
        let base = name.isEmpty ? "Imported Profile" : name
        guard profiles.contains(where: { $0.name == base }) else { return base }
        var suffix = 2
        while profiles.contains(where: { $0.name == "\(base) \(suffix)" }) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    // MARK: - Schedules

    func addSchedule(_ schedule: Schedule, toProfileWithId id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].schedules.append(schedule)
        saveProfiles()
        ScheduleManager.sync(profiles: profiles)
    }

    func updateSchedule(_ schedule: Schedule, inProfileWithId id: UUID) {
        guard let profileIndex = profiles.firstIndex(where: { $0.id == id }),
              let scheduleIndex = profiles[profileIndex].schedules.firstIndex(where: { $0.id == schedule.id }) else { return }
        profiles[profileIndex].schedules[scheduleIndex] = schedule
        saveProfiles()
        ScheduleManager.sync(profiles: profiles)
    }

    func deleteSchedule(withId scheduleId: UUID, fromProfileWithId id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].schedules.removeAll { $0.id == scheduleId }
        saveProfiles()
        ScheduleManager.sync(profiles: profiles)
    }

    private func ensureDefaultProfile() {
        if profiles.isEmpty {
            let defaultProfile = Profile(name: "Default", appTokens: [], categoryTokens: [], icon: "bell.slash")
            profiles.append(defaultProfile)
            currentProfileId = defaultProfile.id
            saveProfiles()
        } else if currentProfileId == nil {
            if let defaultProfile = profiles.first(where: { $0.name == "Default" }) {
                currentProfileId = defaultProfile.id
            } else {
                currentProfileId = profiles.first?.id
            }
            saveProfiles()
        }
    }
}
