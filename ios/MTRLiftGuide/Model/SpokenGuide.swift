//
//  SpokenGuide.swift
//  MTR Lift Guide
//
//  Screen-free narration for guidance. The spoken script never asks the
//  listener to look for signs, arrows or the screen: it describes distance in
//  steps, turning in degrees, and physical cues a blind traveller can act on.
//

import Foundation

enum SpokenGuide {

    /// One bilingual line; `VoiceService` picks the language to synthesise.
    struct Script {
        let zh: String
        let en: String
    }

    // MARK: - Step narration

    static func step(
        index: Int,
        waypoints: [Waypoint],
        line: Line,
        station: Station,
        exit: StationExit,
        mode: RouteMode,
        heading: Double,
        headingAvailable: Bool
    ) -> Script {
        let total = max(waypoints.count, 1)
        let target = RouteEngine.bearing(for: index, total: waypoints.count)
        let coach = RouteEngine.coach(line: line, station: station, exit: exit)
        let estimate = RouteEngine.estimate(line: line, station: station, exit: exit)
        let steps = max(4, Int((Double(estimate.metres) / 0.7).rounded()))

        var zh: String
        var en: String

        switch (index, mode) {
        case (0, _):
            zh = "語音導航開始。第 1 步，共 \(total) 步。請在第 \(coach) 卡車廂下車，下車後先站定。這一段大約 \(estimate.metres) 米，即大約 \(steps) 步。我會逐段報距離和轉向，你不需要看屏幕，也不需要找指示牌。"
            en = "Voice guidance starting. Step 1 of \(total). Get off from coach \(coach), then stand still. This leg is about \(estimate.metres) metres, roughly \(steps) steps. I will call out the distance and the turn at each step, so you do not need the screen or any signs."

        case (1, .lift):
            zh = "第 2 步，共 \(total) 步。現在找升降機。它一般在月台中央，門邊有凸起的按鈕面板，按下往大堂的按鈕。如果摸不到，月台設有無障礙召喚鈴，按下會有站務員前來協助。"
            en = "Step 2 of \(total). Find the lift. It usually sits in the middle of the platform, with a raised button panel beside the door — press the button for the concourse. If you cannot find it, there is an accessible help button on the platform that calls station staff."

        case (1, .escalator):
            zh = "第 2 步，共 \(total) 步。前面是扶梯，扶手在你的右手邊。請先站穩，握住扶手，不要靠在側板。"
            en = "Step 2 of \(total). The escalator is ahead, handrail on your right. Step on, then hold the handrail and do not lean on the side panel."

        case (2, _):
            zh = "第 3 步，共 \(total) 步。前面是閘機，請使用闊閘機，拍卡後繼續直行，大約 \(steps) 步後會到達往 \(exit.id) 出口的通道。"
            en = "Step 3 of \(total). The ticket gates are ahead. Use the wide gate, tap your card, then keep going straight; about \(steps) steps brings you to the passage for Exit \(exit.id)."

        default:
            zh = "最後一步。你已到達 \(exit.id) 出口，出口是 \(exit.nameZh)。語音導航到此結束，如需要協助，出口附近設有求助鈴。"
            en = "Last step. You have arrived at Exit \(exit.id), \(exit.nameEn). Voice guidance ends here. If you need help, there is a call button near the exit."
        }

        let direction = directionSentence(
            heading: heading, target: target, available: headingAvailable)
        zh += " " + direction.zh
        en += " " + direction.en

        return Script(zh: zh, en: en)
    }

    // MARK: - Route overview

    /// What the user hears on the route screen before starting guidance.
    static func overview(
        waypoints: [Waypoint],
        line: Line,
        station: Station,
        exit: StationExit,
        mode: RouteMode
    ) -> Script {
        let total = max(waypoints.count, 1)
        let coach = RouteEngine.coach(line: line, station: station, exit: exit)
        let estimate = RouteEngine.estimate(line: line, station: station, exit: exit)
        let steps = max(4, Int((Double(estimate.metres) / 0.7).rounded()))
        let transportZh = mode == .lift ? "乘升降機" : "乘扶梯"
        let transportEn = mode == .lift ? "take the lift" : "take the escalator"

        return Script(
            zh: "全程共 \(total) 步。先在第 \(coach) 卡車廂下車，然後\(transportZh)往大堂，經閘機前往 \(exit.id) 出口。全程大約 \(estimate.metres) 米，即大約 \(steps) 步。開始導航後，我會逐步報出距離與轉向，你不需要看指示牌。",
            en: "\(total) steps in total. Get off from coach \(coach), \(transportEn) up to the concourse, then pass the ticket gates to Exit \(exit.id). The walk is about \(estimate.metres) metres, roughly \(steps) steps. Once guidance starts I will call out distance and turns — you do not need to read any signs.")
    }

    // MARK: - Direction

    /// Where the target sits relative to where the listener is facing, said in
    /// degrees rather than in localisable references to what is on screen.
    static func directionSentence(
        heading: Double, target: Double, available: Bool
    ) -> Script {
        guard available else {
            return Script(
                zh: "請把身體慢慢轉一圈，我會在你面向正確方向時告訴你。",
                en: "Slowly turn on the spot; I will tell you when you are facing the right way.")
        }

        let delta = normalisedDelta(heading: heading, target: target)
        let magnitude = abs(delta)
        let degrees = max(10, Int((magnitude / 10).rounded()) * 10)

        switch magnitude {
        case ..<15:
            return Script(
                zh: "你現在的方向正確，請繼續直行。",
                en: "You are facing the right way — keep going straight.")
        case ..<60:
            return delta > 0
                ? Script(
                    zh: "目標在你的右前方大約 \(degrees) 度。",
                    en: "The exit is about \(degrees) degrees to your right.")
                : Script(
                    zh: "目標在你的左前方大約 \(degrees) 度。",
                    en: "The exit is about \(degrees) degrees to your left.")
        case ..<125:
            return delta > 0
                ? Script(zh: "請向右轉大約 \(degrees) 度。", en: "Turn right about \(degrees) degrees.")
                : Script(zh: "請向左轉大約 \(degrees) 度。", en: "Turn left about \(degrees) degrees.")
        default:
            return Script(
                zh: "目標在你的後方，請轉身大約 \(degrees) 度。",
                en: "The exit is behind you — turn around about \(degrees) degrees.")
        }
    }

    /// Short correction used while walking; `nil` when the heading is fine.
    static func correction(heading: Double, target: Double) -> Script? {
        let delta = normalisedDelta(heading: heading, target: target)
        let magnitude = abs(delta)
        guard magnitude > 25 else { return nil }

        let degrees = max(10, Int((magnitude / 10).rounded()) * 10)

        if magnitude > 150 {
            return Script(zh: "方向相反，請轉身。", en: "You are facing the opposite way — please turn around.")
        }
        return delta > 0
            ? Script(zh: "向右轉 \(degrees) 度。", en: "Turn right \(degrees) degrees.")
            : Script(zh: "向左轉 \(degrees) 度。", en: "Turn left \(degrees) degrees.")
    }

    /// Positive means the target is clockwise (to the listener's right).
    private static func normalisedDelta(heading: Double, target: Double) -> Double {
        var delta = target - heading
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        guard delta.isFinite else { return 0 }
        return delta
    }
}
