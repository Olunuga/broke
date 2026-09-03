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
    @State private var showWrongTagAlert = false
    @State private var showCreateTagAlert = false
    @State private var showWriteResultAlert = false
    @State private var nfcWriteSuccess = false
    @State private var activeSchedules: [Schedule]
    @State private var suspendedUntil: Date?
    @State private var remainingExtensions: Int
    @State private var isTagRegistered: Bool
    private let refreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// `.onAppear` only fires after SwiftUI has already rendered a first frame with
    /// whatever the `@State` defaults are — reading here instead means that first
    /// frame is already correct, with no gap at all.
    init() {
        _activeSchedules = State(initialValue: SharedStore.activeBlockingSchedules())
        _suspendedUntil = State(initialValue: SharedStore.suspendedUntil)
        _remainingExtensions = State(initialValue: SharedStore.remainingSuspensionExtensions)
        _isTagRegistered = State(initialValue: TagSecret.isRegistered)
    }

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
        .onAppear {
            // Read immediately for a fast first paint. This can occasionally race a
            // background extension callback that hasn't been delivered yet (e.g. one
            // that crossed a schedule boundary while suspended) and show briefly
            // stale data — the 1-second poll below corrects that quickly enough not
            // to read as a flicker, which is a better tradeoff than leaving the
            // screen blank until the first poll tick.
            refreshScheduleBlockingState()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                // sync() re-verifies real enforcement — a missed extension callback
                // (e.g. a wake-up that failed to register) wouldn't show up as wrong
                // otherwise.
                ScheduleManager.sync(profiles: profileManager.profiles)
                refreshScheduleBlockingState()
            }
        }
        .onReceive(refreshTimer) { _ in
            // SharedStore is UserDefaults-backed and doesn't push updates — poll while
            // the screen is open so a schedule starting mid-session shows up on its own.
            // A 1-second interval, not something more relaxed, so the launch/resume
            // race described above corrects fast enough to read as instant rather
            // than as a flicker.
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

            // Shown whether or not anything is currently blocking. A suspension
            // outlives a manual block, so hiding this while manually blocked meant
            // lifting that block revealed nothing about schedules still being
            // suspended.
            if isSuspended {
                Text("Schedules suspended until \(suspendedUntilLabel)")
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

            if isScheduleBlocking {
                extendButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: isBlocked ? geometry.size.height : geometry.size.height / 2)
        .animation(.spring(), value: isBlocked)
    }

    /// Extends the suspension without a tag scan, for when the tag isn't to hand.
    /// Limited per day, so it stays an exception rather than a way around the tag.
    @ViewBuilder
    private var extendButton: some View {
        if remainingExtensions > 0 {
            Button(action: extendSuspension) {
                Text("Extend \(extensionMinutes) min · \(remainingExtensions) left today")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .transition(.scale)
        } else {
            Text("No extensions left today")
                .font(.caption2)
                .opacity(0.6)
                .transition(.scale)
        }
    }

    private var extensionMinutes: Int {
        Int(SharedStore.suspensionExtensionDuration / 60)
    }

    private func extendSuspension() {
        withAnimation(.spring()) {
            ScheduleManager.extendSuspension(profiles: profileManager.profiles)
            refreshScheduleBlockingState()
        }
    }

    private var earlyUnblockMinutesLabel: String {
        "\(Int(SharedStore.suspensionDuration / 60)) minutes"
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
        remainingExtensions = SharedStore.remainingSuspensionExtensions
    }

    private func scanTag() {
        nfcReader.scan { payload in
            guard TagSecret.matches(payload) else {
                showWrongTagAlert = true
                NSLog("Wrong Tag!")
                return
            }

            // Re-check fresh rather than trust `isScheduleBlocking` — that @State can
            // be stale by up to the poll interval, and taking the wrong branch here
            // means the wrong shield gets touched.
            if !SharedStore.activeBlockingSchedules().isEmpty {
                NSLog("Suspending active schedule for \(Int(SharedStore.suspensionDuration / 60)) minutes")
                ScheduleManager.suspendActiveSchedules(for: SharedStore.suspensionDuration, profiles: profileManager.profiles)
            } else {
                NSLog("Toggling block")
                appBlocker.toggleBlocking(for: profileManager.currentProfile)
            }
            refreshScheduleBlockingState()
        }
    }
    
    /// Gated on whether a tag exists, not on `isBlocked`. Until one is registered this
    /// stays available even while blocking, since a schedule starts without a tag scan
    /// and would otherwise leave no way to create the only thing that can suspend it.
    /// Once a tag exists, writing another while blocked would be a way around the
    /// physical tag, so the button goes away until blocking ends.
    @ViewBuilder
    private var createTagButton: some View {
        if !isTagRegistered || !isBlocked {
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
    
    /// Generates the secret before writing, so a failed write leaves a stored hash
    /// with no matching tag. Writing again recovers from that; the alternative —
    /// storing only after a successful write — would leave a valid tag in the world
    /// that the app doesn't recognise, which is worse.
    private func createBrokerTag() {
        guard let secret = TagSecret.generate() else {
            nfcWriteSuccess = false
            showCreateTagAlert = false
            showWriteResultAlert = true
            return
        }

        nfcReader.write(secret) { success in
            nfcWriteSuccess = success
            showCreateTagAlert = false
            showWriteResultAlert = true
            isTagRegistered = TagSecret.isRegistered
        }
    }
}
