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

struct SuspensionActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SuspensionActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "lock.open.fill")
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Blocking paused")
                        .font(.headline)
                    Text(context.state.detail)
                        .font(.caption)
                        .opacity(0.8)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.state.resumesAt, style: .timer)
                        .font(.headline)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                    Text("until it resumes")
                        .font(.caption2)
                        .opacity(0.7)
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "lock.open.fill")
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.resumesAt, style: .timer)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Blocking paused")
                            .font(.headline)
                        Text(context.state.detail)
                            .font(.caption)
                            .opacity(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "lock.open.fill")
            } compactTrailing: {
                Text(context.state.resumesAt, style: .timer)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: "lock.open.fill")
            }
        }
    }
}
