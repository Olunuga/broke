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
    #if DEBUG
    private static let earlyUnblockDuration: TimeInterval = 2 * 60
    #else
    private static let earlyUnblockDuration: TimeInterval = 30 * 60
    #endif

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
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                // sync() re-verifies real enforcement — a missed extension callback
                // (e.g. a wake-up that failed to register) wouldn't show up as wrong
                // otherwise. It does not, on its own, drive the display: reading
                // SharedStore for display immediately after resuming caught a
                // transient state where a background extension callback that crossed
                // a schedule boundary while the app was suspended hadn't been
                // delivered yet, showing a schedule then hiding it again — the poll
                // timer's next tick, a few seconds later, always had the correct
                // answer. Leaving the display to that same poll avoids the gap.
                ScheduleManager.sync(profiles: profileManager.profiles)
            }
        }
        .onReceive(refreshTimer) { _ in
            // SharedStore is UserDefaults-backed and doesn't push updates — poll while
            // the screen is open so a schedule starting mid-session shows up on its own.
            // This is also the display's only source at launch and on resume, not just
            // its periodic top-up — see the scenePhase comment above for why an
            // immediate read at either of those moments isn't trustworthy.
            refreshScheduleBlockingState()
        }
    }

    @ViewBuilder
    private func blockOrUnblockButton(geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            if isBlocked {
                Text("Blocking Active")
                    .font(.headline)
                    .fontWeight(.bold)
                    .transition(.scale)
            }

            if appBlocker.isBlocking {
                Text("Blocked manually")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .opacity(0.85)
                    .transition(.scale)
            }

            if !activeSchedules.isEmpty {
                VStack(spacing: 6) {
                    ForEach(activeSchedules) { schedule in
                        VStack(spacing: 1) {
                            Text("\(schedule.name) · \(schedule.mode.label)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                            Text(scheduleDetailLabel(for: schedule))
                                .font(.caption2)
                                .opacity(0.7)
                        }
                    }
                }
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
        if let transitionLabel = nextTransitionLabel(for: schedule) {
            label += " · \(transitionLabel)"
        }
        return label
    }

    /// Countdown to the window opening or closing — not to the budget running out,
    /// which Apple's DeviceActivity framework never exposes to a third-party app.
    /// `wantsBlock()` alone (not suspension or the outside-window budget) decides
    /// whether the next transition blocks or unblocks, since this is a display of the
    /// window's own schedule, not of everything currently affecting enforcement.
    private func nextTransitionLabel(for schedule: Schedule) -> String? {
        guard let next = schedule.nextTransition() else { return nil }
        let totalMinutes = Int(next.timeIntervalSinceNow / 60)
        guard totalMinutes >= 0 else { return nil }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let durationLabel = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        let verb = schedule.wantsBlock() ? "unblocks" : "blocks"
        return "\(verb) in \(durationLabel)"
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
    
    /// Hidden, not just disabled, while anything is blocking — otherwise anyone with
    /// a blank NFC tag could mint a new valid one on the spot, making the physical
    /// tag requirement meaningless.
    @ViewBuilder
    private var createTagButton: some View {
        if !isBlocked {
            Button(action: {
                showCreateTagAlert = true
            }) {
                Image(systemName: "plus")
            }
            .disabled(!NFCNDEFReaderSession.readingAvailable)
        }
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