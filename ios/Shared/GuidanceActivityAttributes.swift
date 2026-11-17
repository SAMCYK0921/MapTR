//
//  GuidanceActivityAttributes.swift
//  Shared between the app and the widget extension.
//
//  Live Activity (Dynamic Island) for AR in-station guidance.
//

import ActivityKit
import Foundation

/// One step shown in the expanded Dynamic Island checklist.
struct GuidanceStep: Codable, Hashable {
    let title: String      // localized instruction title
    let symbol: String     // SF Symbol for the step
}

struct GuidanceActivityAttributes: ActivityAttributes {

    public struct ContentState: Codable, Hashable {
        var stepIndex: Int      // 0-based current waypoint
        var totalSteps: Int
        var stepTitle: String   // current instruction title
        var hint: String        // short direction hint
        var directionSymbol: String   // compass arrow (arrow.up / turn left / right / uturn)
        var directionText: String     // e.g. "前方左轉" / "Turn left ahead"
        var modeSymbol: String        // lift / escalator icon
        var modeTitle: String         // e.g. "全程電梯" / "Lift all the way"
        var steps: [GuidanceStep]     // full step list for the expanded island
    }

    var stationName: String
    var exitID: String
}
