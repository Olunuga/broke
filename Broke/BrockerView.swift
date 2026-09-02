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
    @State private var activeSchedules: [Schedule] = []
    @State private var suspendedUntil: Date?
    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var isScheduleBlocking: Bool {
        !activeSchedules.isEmpty
    }

    private var activeScheduleNames: [String] {
        activeSchedules.map { $0.name }
    }

    /// A suspension makes `isScheduleBlocking` false the same as "nothing scheduled"
    /// — this is what lets the screen tell the two apart.
    private var isSuspended: Bool {
        guard let suspendedUntil else { return false }
        return Date() < suspendedUntil
    }

    private var suspendedUntilLabel: String {
        guard let suspendedUntil else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: suspendedUntil)
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

                            if isSuspended {
                                Text("Schedules suspended until \(suspendedUntilLabel)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                            }

                            ProfilesPicker(profileManager: profileManager)
                                .frame(height: geometry.size.height / 2)
                                .transition(.move(edge: .bottom))
                        }
                    }
                    .background(isBlocked ? Color("BlockingBackground") : Color("NonBlockingBackground"))
                }
            }
            .navigationBarItems(leading: debugSuspensionControl, trailing: createTagButton)
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
        .onReceive(refreshTimer) { _ in
            // SharedStore is UserDefaults-backed and doesn't push updates — poll while
            // the screen is open so a schedule starting mid-session shows up on its own.
            refreshScheduleBlockingState()
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

            ForEach(activeSchedules) { schedule in
                Text(scheduleDetailLabel(for: schedule))
                    .font(.caption2)
                    .opacity(0.7)
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

    private var earlyUnblockMinutesLabel: String {
        "\(Int(Self.earlyUnblockDuration / 60)) minutes"
    }

    private var blockButtonLabel: String {
        if isScheduleBlocking {
            return appBlocker.isBlocking
                ? "Tap to suspend the schedule for \(earlyUnblockMinutesLabel) (manual block stays on)"
                : "Tap to suspend this block for \(earlyUnblockMinutesLabel)"
        }
        return appBlocker.isBlocking ? "Tap to unblock" : "Tap to block"
    }

    private func scheduleDetailLabel(for schedule: Schedule) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let start = Calendar.current.date(from: schedule.startTime) ?? Date()
        let end = Calendar.current.date(from: schedule.endTime) ?? Date()
        var label = "\(formatter.string(from: start))–\(formatter.string(from: end))"
        if schedule.mode == .allow, let budgetMinutes = schedule.budgetMinutes {
            label += " · \(budgetMinutes) min/day limit"
        }
        return label
    }

    private func refreshScheduleBlockingState() {
        activeSchedules = SharedStore.activeBlockingSchedules()
        suspendedUntil = SharedStore.suspendedUntil
    }

    private func scanTag() {
        nfcReader.scan { payload in
            guard payload == tagPhrase else {
                showWrongTagAlert = true
                NSLog("Wrong Tag!\nPayload: \(payload)")
                return
            }

            // Re-check fresh rather than trust `isScheduleBlocking` — that @State can
            // be stale by up to the poll interval, and taking the wrong branch here
            // means the wrong shield gets touched.
            if !SharedStore.activeBlockingSchedules().isEmpty {
                NSLog("Suspending active schedule for \(Int(Self.earlyUnblockDuration / 60)) minutes")
                ScheduleManager.suspendActiveSchedules(for: Self.earlyUnblockDuration, profiles: profileManager.profiles)
            } else {
                NSLog("Toggling block")
                appBlocker.toggleBlocking(for: profileManager.currentProfile)
            }
            refreshScheduleBlockingState()
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

    /// Debug builds only — a suspension is otherwise only clearable by waiting it out
    /// or scanning the tag again, both slow when iterating on schedule changes.
    @ViewBuilder
    private var debugSuspensionControl: some View {
        #if DEBUG
        if isSuspended {
            Button(action: clearSuspensionForTesting) {
                Image(systemName: "clock.badge.xmark")
            }
        }
        #endif
    }

    #if DEBUG
    private func clearSuspensionForTesting() {
        SharedStore.suspendedUntil = nil
        ScheduleManager.sync(profiles: profileManager.profiles)
        refreshScheduleBlockingState()
    }
    #endif
    
    private func createBrokerTag() {
        nfcReader.write(tagPhrase) { success in
            nfcWriteSuccess = success
            showCreateTagAlert = false
            showWriteResultAlert = true
        }
    }
}