//
//  AppBlocker.swift
//  Broke
//
//  Created by Oz Tamir on 22/08/2024.
//
import SwiftUI
import ManagedSettings
import FamilyControls

class AppBlocker: ObservableObject {
    let store = SharedStore.managedSettingsStore
    @Published var isBlocking = false
    @Published var isAuthorized = false
    
    init() {
        loadBlockingState()
        Task {
            await requestAuthorization()
        }
    }
    
    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            DispatchQueue.main.async {
                self.isAuthorized = true
            }
        } catch {
            print("Failed to request authorization: \(error)")
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
        }
    }
    
    func toggleBlocking(for profile: Profile) {
        guard isAuthorized else {
            print("Not authorized to block apps")
            return
        }
        
        isBlocking.toggle()
        saveBlockingState()
        applyBlockingSettings(for: profile)
    }
    
    func applyBlockingSettings(for profile: Profile) {
        if isBlocking {
            BrokeLog.log("manual block on: profile='\(profile.name)' apps=\(profile.appTokens.count) categories=\(profile.categoryTokens.count) web=\(profile.webDomainTokens.count)")
            ShieldWriter.apply(profile, to: store)
        } else {
            BrokeLog.log("manual block off")
            ShieldWriter.clear(store)
        }
        HardeningManager.refresh()
    }
    
    private func loadBlockingState() {
        isBlocking = SharedStore.defaults.bool(forKey: "isBlocking")
    }
    
    private func saveBlockingState() {
        SharedStore.defaults.set(isBlocking, forKey: "isBlocking")
    }
}