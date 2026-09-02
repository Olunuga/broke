//
//  ScheduleFormView.swift
//  Broke
//

import SwiftUI

struct ScheduleFormView: View {
    @ObservedObject var profileManager: ProfileManager
    let profileId: UUID
    let existingSchedule: Schedule?
    let onDismiss: () -> Void

    @State private var name: String
    @State private var mode: ScheduleMode
    @State private var weekdays: Set<Int>
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var hasBudget: Bool
    @State private var budgetMinutes: Int
    @State private var isEnabled: Bool
    @State private var showDeleteConfirmation = false

    private let weekdaySymbols: [(number: Int, label: String)] =
        Calendar.current.veryShortWeekdaySymbols.enumerated().map { index, label in (index + 1, label) }

    init(profileManager: ProfileManager, profileId: UUID, existingSchedule: Schedule?, onDismiss: @escaping () -> Void) {
        self.profileManager = profileManager
        self.profileId = profileId
        self.existingSchedule = existingSchedule
        self.onDismiss = onDismiss

        _name = State(initialValue: existingSchedule?.name ?? "")
        _mode = State(initialValue: existingSchedule?.mode ?? .block)
        _weekdays = State(initialValue: existingSchedule?.weekdays ?? [])
        _startTime = State(initialValue: Self.date(from: existingSchedule?.startTime ?? DateComponents(hour: 9, minute: 0)))
        _endTime = State(initialValue: Self.date(from: existingSchedule?.endTime ?? DateComponents(hour: 17, minute: 0)))
        _hasBudget = State(initialValue: existingSchedule?.budgetMinutes != nil)
        _budgetMinutes = State(initialValue: existingSchedule?.budgetMinutes ?? 30)
        _isEnabled = State(initialValue: existingSchedule?.isEnabled ?? true)
    }

    private static func date(from components: DateComponents) -> Date {
        Calendar.current.date(from: components) ?? Date()
    }

    private var durationMinutes: Int {
        let start = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        let end = Calendar.current.dateComponents([.hour, .minute], from: endTime)
        let startTotal = (start.hour ?? 0) * 60 + (start.minute ?? 0)
        let endTotal = (end.hour ?? 0) * 60 + (end.minute ?? 0)
        return endTotal - startTotal
    }

    private var validationError: String? {
        if weekdays.isEmpty {
            return "Pick at least one day."
        }
        if durationMinutes <= 0 {
            return "End time must be after start time. A window can't cross midnight — use two schedules instead."
        }
        if durationMinutes < Schedule.minimumDurationMinutes {
            return "Window must be at least \(Schedule.minimumDurationMinutes) minutes."
        }
        if hasBudget && budgetMinutes < 1 {
            return "Daily limit must be at least 1 minute."
        }
        return nil
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Name")) {
                    TextField("e.g. School Hours", text: $name)
                }

                Section(header: Text("Mode")) {
                    Picker("Mode", selection: $mode) {
                        ForEach(ScheduleMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(mode.explanation)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("Days")) {
                    HStack(spacing: 4) {
                        ForEach(weekdaySymbols, id: \.number) { day in
                            Button(action: { toggle(day.number) }) {
                                Text(day.label)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(weekdays.contains(day.number) ? Color.accentColor : Color.secondary.opacity(0.15))
                                    .foregroundColor(weekdays.contains(day.number) ? .white : .primary)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section(header: Text("Window")) {
                    DatePicker("Start", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("End", selection: $endTime, displayedComponents: .hourAndMinute)
                }

                Section(header: Text("Daily Limit")) {
                    Toggle("Limit time within the window", isOn: $hasBudget)
                    if hasBudget {
                        Stepper("\(budgetMinutes) minutes", value: $budgetMinutes, in: 1...max(durationMinutes, 1), step: 5)
                    }
                }

                Section {
                    Toggle("Enabled", isOn: $isEnabled)
                }

                if let validationError {
                    Section {
                        Text(validationError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                if existingSchedule != nil {
                    Section {
                        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                            Text("Delete Schedule")
                        }
                    }
                }
            }
            .navigationTitle(existingSchedule == nil ? "Add Schedule" : "Edit Schedule")
            .navigationBarItems(
                leading: Button("Cancel", action: onDismiss),
                trailing: Button("Save", action: save)
                    .disabled(name.isEmpty || validationError != nil)
            )
            .alert("Delete Schedule", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    if let existingSchedule {
                        profileManager.deleteSchedule(withId: existingSchedule.id, fromProfileWithId: profileId)
                    }
                    onDismiss()
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private func toggle(_ day: Int) {
        if weekdays.contains(day) {
            weekdays.remove(day)
        } else {
            weekdays.insert(day)
        }
    }

    private func save() {
        guard validationError == nil else { return }

        let start = Calendar.current.dateComponents([.hour, .minute], from: startTime)
        let end = Calendar.current.dateComponents([.hour, .minute], from: endTime)

        let schedule = Schedule(
            id: existingSchedule?.id ?? UUID(),
            name: name,
            mode: mode,
            weekdays: weekdays,
            startTime: DateComponents(hour: start.hour, minute: start.minute),
            endTime: DateComponents(hour: end.hour, minute: end.minute),
            budgetMinutes: hasBudget ? budgetMinutes : nil,
            isEnabled: isEnabled
        )

        if existingSchedule != nil {
            profileManager.updateSchedule(schedule, inProfileWithId: profileId)
        } else {
            profileManager.addSchedule(schedule, toProfileWithId: profileId)
        }
        onDismiss()
    }
}
