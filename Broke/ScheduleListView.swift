//
//  ScheduleListView.swift
//  Broke
//

import SwiftUI

struct ScheduleListView: View {
    @ObservedObject var profileManager: ProfileManager
    let profileId: UUID

    @State private var showAddSchedule = false
    @State private var editingSchedule: Schedule?

    private var schedules: [Schedule] {
        profileManager.profiles.first(where: { $0.id == profileId })?.schedules ?? []
    }

    var body: some View {
        List {
            if schedules.isEmpty {
                Text("No schedules yet. Add one to block or allow this profile automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(schedules) { schedule in
                    Button {
                        editingSchedule = schedule
                    } label: {
                        ScheduleRow(schedule: schedule)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteSchedules)
            }
        }
        .navigationTitle("Schedules")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showAddSchedule = true }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddSchedule) {
            ScheduleFormView(profileManager: profileManager, profileId: profileId, existingSchedule: nil) {
                showAddSchedule = false
            }
        }
        .sheet(item: $editingSchedule) { schedule in
            ScheduleFormView(profileManager: profileManager, profileId: profileId, existingSchedule: schedule) {
                editingSchedule = nil
            }
        }
    }

    private func deleteSchedules(at offsets: IndexSet) {
        for index in offsets {
            profileManager.deleteSchedule(withId: schedules[index].id, fromProfileWithId: profileId)
        }
    }
}

private struct ScheduleRow: View {
    let schedule: Schedule

    private var daysLabel: String {
        guard schedule.weekdays.count < 7 else { return "Every day" }
        let symbols = Calendar.current.veryShortWeekdaySymbols
        return schedule.weekdays.sorted()
            .compactMap { $0 >= 1 && $0 <= 7 ? symbols[$0 - 1] : nil }
            .joined(separator: " ")
    }

    private var timeLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let start = Calendar.current.date(from: schedule.startTime) ?? Date()
        let end = Calendar.current.date(from: schedule.endTime) ?? Date()
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(schedule.name)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
                Text(schedule.mode.label)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
                if !schedule.isEnabled {
                    Text("Off")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Text("\(daysLabel) · \(timeLabel)")
                .font(.caption)
                .foregroundColor(.secondary)
            if let budgetMinutes = schedule.budgetMinutes {
                Text("\(budgetMinutes) min/day limit")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(schedule.isEnabled ? 1 : 0.5)
    }
}
