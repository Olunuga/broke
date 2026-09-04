//
//  EditProfileView.swift
//  Broke
//
//  Created by Oz Tamir on 23/08/2024.
//

import SwiftUI
import SFSymbolsPicker
import FamilyControls

struct ProfileFormView: View {
    @ObservedObject var profileManager: ProfileManager
    @State private var profileName: String
    @State private var profileIcon: String
    @State private var showSymbolsPicker = false
    @State private var showAppSelection = false
    @State private var activitySelection: FamilyActivitySelection
    @State private var restrictWebToAllowlist: Bool
    @State private var showDeleteConfirmation = false
    let profile: Profile?
    let onDismiss: () -> Void

    /// `ProfilesPicker`, the only path to this view, opens it only after a tag scan.
    /// This guards the case where blocking starts (a schedule triggers) while the
    /// sheet is already open, rather than relying on it being torn down implicitly
    /// when its presenting ancestor leaves the view tree.
    private let lockGuardTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    init(profile: Profile? = nil, profileManager: ProfileManager, onDismiss: @escaping () -> Void) {
        self.profile = profile
        self.profileManager = profileManager
        self.onDismiss = onDismiss
        _profileName = State(initialValue: profile?.name ?? "")
        _profileIcon = State(initialValue: profile?.icon ?? "bell.slash")
        _restrictWebToAllowlist = State(initialValue: profile?.restrictWebToAllowlist ?? false)

        var selection = FamilyActivitySelection()
        selection.applicationTokens = profile?.appTokens ?? []
        selection.categoryTokens = profile?.categoryTokens ?? []
        selection.webDomainTokens = profile?.webDomainTokens ?? []
        _activitySelection = State(initialValue: selection)
    }

    private var currentSchedules: [Schedule] {
        guard let profile else { return [] }
        return profileManager.profiles.first(where: { $0.id == profile.id })?.schedules ?? []
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Profile Details")) {
                    VStack(alignment: .leading) {
                        Text("Profile Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Enter profile name", text: $profileName)
                    }
                    
                    Button(action: { showSymbolsPicker = true }) {
                        HStack {
                            Image(systemName: profileIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                            Text("Choose Icon")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("App Configuration")) {
                    Button(action: { showAppSelection = true }) {
                        Text("Configure Blocked Apps")
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Blocked Apps:")
                            Spacer()
                            Text("\(activitySelection.applicationTokens.count)")
                                .fontWeight(.bold)
                        }
                        HStack {
                            Text("Blocked Categories:")
                            Spacer()
                            Text("\(activitySelection.categoryTokens.count)")
                                .fontWeight(.bold)
                        }
                        HStack {
                            Text("Blocked Websites:")
                            Spacer()
                            Text("\(activitySelection.webDomainTokens.count)")
                                .fontWeight(.bold)
                        }
                        Text("Broke can't list the names of the apps due to privacy concerns, it is only able to see the amount of apps selected in the configuration screen.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Toggle("Restrict web to allowed sites only", isOn: $restrictWebToAllowlist)
                    Text(restrictWebToAllowlist
                         ? "Only the websites above are reachable. Everything else is blocked."
                         : "The websites above are blocked. Everything else is reachable.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let profile {
                    Section(header: Text("Schedules")) {
                        NavigationLink {
                            ScheduleListView(profileManager: profileManager, profileId: profile.id)
                        } label: {
                            HStack {
                                Text("Manage Schedules")
                                Spacer()
                                Text("\(currentSchedules.count)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                if profile != nil {
                    Section {
                        Button(action: { showDeleteConfirmation = true }) {
                            Text("Delete Profile")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle(profile == nil ? "Add Profile" : "Edit Profile")
            .navigationBarItems(
                leading: Button("Cancel", action: onDismiss),
                trailing: Button("Save", action: handleSave)
                    .disabled(profileName.isEmpty)
            )
            .sheet(isPresented: $showSymbolsPicker) {
                SymbolsPicker(selection: $profileIcon, title: "Pick an icon", autoDismiss: true)
            }
            .sheet(isPresented: $showAppSelection) {
                NavigationView {
                    FamilyActivityPicker(selection: $activitySelection)
                        .navigationTitle("Select Apps")
                        .navigationBarItems(trailing: Button("Done") {
                            showAppSelection = false
                        })
                }
            }
            .alert(isPresented: $showDeleteConfirmation) {
                Alert(
                    title: Text("Delete Profile"),
                    message: Text("Are you sure you want to delete this profile?"),
                    primaryButton: .destructive(Text("Delete")) {
                        if let profile = profile {
                            profileManager.deleteProfile(withId: profile.id)
                        }
                        onDismiss()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .onAppear { dismissIfBlocking() }
        .onReceive(lockGuardTimer) { _ in dismissIfBlocking() }
    }

    private func dismissIfBlocking() {
        if SharedStore.isAnythingBlocking {
            onDismiss()
        }
    }
    
    private func handleSave() {
        if let existingProfile = profile {
            profileManager.updateProfile(
                id: existingProfile.id,
                name: profileName,
                appTokens: activitySelection.applicationTokens,
                categoryTokens: activitySelection.categoryTokens,
                webDomainTokens: activitySelection.webDomainTokens,
                restrictWebToAllowlist: restrictWebToAllowlist,
                icon: profileIcon
            )
        } else {
            let newProfile = Profile(
                name: profileName,
                appTokens: activitySelection.applicationTokens,
                categoryTokens: activitySelection.categoryTokens,
                webDomainTokens: activitySelection.webDomainTokens,
                restrictWebToAllowlist: restrictWebToAllowlist,
                icon: profileIcon
            )
            profileManager.addProfile(newProfile: newProfile)
        }
        onDismiss()
    }
}
