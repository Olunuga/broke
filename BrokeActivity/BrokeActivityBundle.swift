//
//  BrokeActivityBundle.swift
//  BrokeActivity
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct BrokeActivityBundle: WidgetBundle {
    var body: some Widget {
        SuspensionActivityWidget()
    }
}

/// A bounded countdown, not an open-ended one from a date: `Text(_:style:.timer)`
/// counts upwards once the date passes, and nothing redraws the card to stop it.
struct SuspensionCountdown: View {
    let state: SuspensionActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if isStale {
            Text("0:00")
                .monospacedDigit()
        } else {
            Text(timerInterval: state.countdownRange, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

struct SuspensionActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SuspensionActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.isStale ? "lock.fill" : "lock.open.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.isStale ? "Blocking resumed" : "Blocking paused")
                        .font(.headline)
                    Text(context.state.detail)
                        .font(.caption)
                        .opacity(0.8)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    SuspensionCountdown(state: context.state, isStale: context.isStale)
                        .font(.headline)
                    Text(context.isStale ? "blocking is back on" : "until it resumes")
                        .font(.caption2)
                        .opacity(0.7)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.isStale ? "lock.fill" : "lock.open.fill")
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SuspensionCountdown(state: context.state, isStale: context.isStale)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.isStale ? "Blocking resumed" : "Blocking paused")
                            .font(.headline)
                        Text(context.state.detail)
                            .font(.caption)
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: context.isStale ? "lock.fill" : "lock.open.fill")
            } compactTrailing: {
                SuspensionCountdown(state: context.state, isStale: context.isStale)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: context.isStale ? "lock.fill" : "lock.open.fill")
            }
        }
    }
}
