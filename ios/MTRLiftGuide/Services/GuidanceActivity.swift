//
//  GuidanceActivity.swift
//  MTR Lift Guide
//
//  Starts, updates and ends the Dynamic Island Live Activity that mirrors the
//  AR guidance progress (current waypoint, station → exit, step counter,
//  compass direction and travel mode).
//

import ActivityKit
import Foundation

@MainActor
final class GuidanceActivity {
    static let shared = GuidanceActivity()

    private var activity: Activity<GuidanceActivityAttributes>?

    private var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(stationName: String, exitID: String,
               state: GuidanceActivityAttributes.ContentState) {
        guard isEnabled else { return }
        let attributes = GuidanceActivityAttributes(stationName: stationName, exitID: exitID)
        do {
            activity = try Activity.request(attributes: attributes,
                                            content: .init(state: state, staleDate: nil))
        } catch {
            print("[LiveActivity] start failed: \(error)")
        }
    }

    func update(state: GuidanceActivityAttributes.ContentState) {
        guard let activity else { return }
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        // Capture the reference first: the async end() must run against a
        // non-nil activity, otherwise clearing `activity` before the Task body
        // executes would silently skip ending and leave the island stuck.
        let activityToEnd = activity
        activity = nil
        guard let activityToEnd else { return }
        Task { await activityToEnd.end(nil, dismissalPolicy: .immediate) }
    }
}
