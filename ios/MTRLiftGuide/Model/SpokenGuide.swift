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

    /// Where the target sits relative to where the listener is facing, said on a
    /// clock face (12 = straight ahead, 3 = right, 9 = left) — the frame blind
    /// travellers actually use, instead of bearing degrees.
    static func directionSentence(
        heading: Double, target: Double, available: Bool
    ) -> Script {
        guard available else {
            return Script(
                zh: "請把手機放低，慢慢轉動身體；當你面向正確方向時，我會用鐘面方向告訴你。",
                en: "Slowly turn on the spot; I will give you the direction on a clock face once you face the right way.")
        }

        let delta = normalisedDelta(heading: heading, target: target)
        let magnitude = abs(delta)
        let hour = clockHour(delta)

        switch magnitude {
        case ..<15:
            return Script(
                zh: "方向正確，目標在你正前方，即 12 點鐘方向；請繼續直行。",
                en: "You are facing the right way — the exit is straight ahead at 12 o'clock. Keep going.")
        case ..<60:
            return delta > 0
                ? Script(
                    zh: "目標在你的 \(hour) 點鐘方向，請稍微向右轉，然後直行。",
                    en: "The exit is at your \(hour) o'clock. Turn slightly right, then go straight.")
                : Script(
                    zh: "目標在你的 \(hour) 點鐘方向，請稍微向左轉，然後直行。",
                    en: "The exit is at your \(hour) o'clock. Turn slightly left, then go straight.")
        case ..<125:
            return delta > 0
                ? Script(
                    zh: "請向右轉，目標在你的 \(hour) 點鐘方向。",
                    en: "Turn right — the exit is at your \(hour) o'clock.")
                : Script(
                    zh: "請向左轉，目標在你的 \(hour) 點鐘方向。",
                    en: "Turn left — the exit is at your \(hour) o'clock.")
        default:
            return Script(
                zh: "目標在你身後，大約 \(hour) 點鐘方向，請轉身。",
                en: "The exit is behind you, around your \(hour) o'clock — please turn around.")
        }
    }

    /// Short correction used while walking; `nil` when the heading is fine.
    static func correction(heading: Double, target: Double) -> Script? {
        let delta = normalisedDelta(heading: heading, target: target)
        let magnitude = abs(delta)
        guard magnitude > 25 else { return nil }

        let hour = clockHour(delta)

        if magnitude > 150 {
            return Script(
                zh: "方向相反，目標在你身後約 \(hour) 點鐘方向，請轉身。",
                en: "You are facing the opposite way — the exit is around your \(hour) o'clock. Please turn around.")
        }
        return delta > 0
            ? Script(zh: "目標在你 \(hour) 點鐘方向，請向右轉。",
                     en: "The exit is at your \(hour) o'clock — turn right.")
            : Script(zh: "目標在你 \(hour) 點鐘方向，請向左轉。",
                     en: "The exit is at your \(hour) o'clock — turn left.")
    }

    /// Compass delta → clock face: straight ahead is 12, a quarter turn right is 3.
    private static func clockHour(_ delta: Double) -> Int {
        var hour = Int((delta / 30).rounded()) % 12
        if hour <= 0 { hour += 12 }
        return hour
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
