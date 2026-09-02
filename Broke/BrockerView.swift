//
//  BrockerView.swift
//  Broke
//
//  Created by Oz Tamir on 22/08/2024.
//
import SwiftUI
import CoreNFC
import SFSymbolsPicker
import FamilyControls
import ManagedSettings

struct BrokerView: View {
    @EnvironmentObject private var appBlocker: AppBlocker
    @EnvironmentObject private var profileManager: ProfileManager
    @StateObject private var nfcReader = NFCReader()
    @Environment(\.scenePhase) private var scenePhase
    private let tagPhrase = "BROKE-IS-GREAT"
    private static let earlyUnblockDuration: TimeInterval = 30 * 60

    @State private var showWrongTagAlert = false
    @State private var showCreateTagAlert = false
    @State private var showWriteResultAlert = false
    @State private var nfcWriteSuccess = false
    @State private var activeScheduleNames: [String] = []

    private var isScheduleBlocking: Bool {
        !activeScheduleNames.isEmpty
    }

    /// The manual toggle and any active schedule are independent shield sources; the
    /// home screen shows blocked if either one is.
    private var isBlocked: Bool {
        appBlocker.isBlocking || isScheduleBlocking
    }

    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    VStack(spacing: 0) {
                        blockOrUnblockButton(geometry: geometry)

                        if !isBlocked {
                            Divider()

                            ProfilesPicker(profileManager: profileManager)
                                .frame(height: geometry.size.height / 2)
                                .transition(.move(edge: .bottom))
                        }
                    }
                    .background(isBlocked ? Color("BlockingBackground") : Color("NonBlockingBackground"))
                }
            }
            .navigationBarItems(trailing: createTagButton)
            .alert(isPresented: $showWrongTagAlert) {
                Alert(
                    title: Text("Not a Broker Tag"),
                    message: Text("You can create a new Broker tag using the + button"),
                    dismissButton: .default(Text("OK"))
                )
            }
            .alert("Create Broker Tag", isPresented: $showCreateTagAlert) {
                Button("Create") { createBrokerTag() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Do you want to create a new Broker tag?")
            }
            .alert("Tag Creation", isPresented: $showWriteResultAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(nfcWriteSuccess ? "Broker tag created successfully!" : "Failed to create Broker tag. Please try again.")
            }
        }
        .animation(.spring(), value: isBlocked)
        .onAppear { refreshScheduleBlockingState() }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                refreshScheduleBlockingState()
            }
        }
    }

    @ViewBuilder
    private func blockOrUnblockButton(geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            if let blockSourceDescription {
                Text(blockSourceDescription)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .opacity(0.85)
                    .transition(.scale)
            }

            Text(blockButtonLabel)
                .font(.caption)
                .opacity(0.75)
                .transition(.scale)

            Button(action: {
                withAnimation(.spring()) {
                    scanTag()
                }
            }) {
                Image(isBlocked ? "RedIcon" : "GreenIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: geometry.size.height / 3)
            }
            .transition(.scale)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: isBlocked ? geometry.size.height : geometry.size.height / 2)
        .animation(.spring(), value: isBlocked)
    }

    private var blockSourceDescription: String? {
        switch (appBlocker.isBlocking, isScheduleBlocking) {
        case (true, true):
            return "Blocked manually, and by schedule: \(activeScheduleNames.joined(separator: ", "))"
        case (true, false):
            return "Blocked manually"
        case (false, true):
            return "Blocked by schedule: \(activeScheduleNames.joined(separator: ", "))"
        case (false, false):
            return nil
        }
    }

    private var blockButtonLabel: String {
        if isScheduleBlocking {
            return appBlocker.isBlocking
                ? "Tap to end the schedule early (manual block stays on)"
                : "Tap to end this block early"
        }
        return appBlocker.isBlocking ? "Tap to unblock" : "Tap to block"
    }

    private func refreshScheduleBlockingState() {
        activeScheduleNames = SharedStore.activeBlockingScheduleNames()
    }

    private func scanTag() {
        nfcReader.scan { payload in
            guard payload == tagPhrase else {
                showWrongTagAlert = true
                NSLog("Wrong Tag!\nPayload: \(payload)")
                return
            }

            if isScheduleBlocking {
                NSLog("Suspending active schedule for \(Int(Self.earlyUnblockDuration / 60)) minutes")
                ScheduleManager.suspendActiveSchedules(for: Self.earlyUnblockDuration, profiles: profileManager.profiles)
                refreshScheduleBlockingState()
            } else {
                NSLog("Toggling block")
                appBlocker.toggleBlocking(for: profileManager.currentProfile)
            }
        }
    }
    
    private var createTagButton: some View {
        Button(action: {
            showCreateTagAlert = true
        }) {
            Image(systemName: "plus")
        }
        .disabled(!NFCNDEFReaderSession.readingAvailable)
    }
    
    private func createBrokerTag() {
        nfcReader.write(tagPhrase) { success in
            nfcWriteSuccess = success
            showCreateTagAlert = false
            showWriteResultAlert = true
        }
    }
}