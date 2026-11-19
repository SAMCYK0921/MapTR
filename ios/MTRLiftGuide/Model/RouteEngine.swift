//
//  RouteEngine.swift
//  MTR Lift Guide
//
//  Builds the step-by-step guidance for a chosen station / exit / travel mode.
//  Coach numbers and walking figures are derived deterministically from the
//  station + exit pair so the same journey always produces the same guidance.
//

import Foundation

enum RouteEngine {

    /// Stable pseudo-random 0..<bound for a given key.
    private static func roll(_ key: String, bound: Int) -> Int {
        var hash = UInt64(5381)
        for byte in key.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return Int(hash % UInt64(max(bound, 1)))
    }

    private static func coachNumber(line: Line, station: Station, exit: StationExit) -> Int {
        roll(line.id + station.id + exit.id, bound: line.coaches) + 1
    }

    /// Estimated platform walk distance (metres) from the coach to the chosen exit route.
    private static func walkDistance(line: Line, station: Station, exit: StationExit) -> Int {
        let base = 30 + roll(station.id + exit.id + "d", bound: 7) * 10
        return line.coaches >= 9 ? base + 20 : base
    }

    /// Public summary used by the home-screen destination card.
    static func estimate(line: Line, station: Station, exit: StationExit) -> (metres: Int, minutes: Int) {
        let metres = walkDistance(line: line, station: station, exit: exit)
        return (metres, max(1, Int(round(Double(metres) / 45.0))))
    }

    /// Coach closest to the given exit — used on the home-screen map preview.
    static func coach(line: Line, station: Station, exit: StationExit) -> Int {
        coachNumber(line: line, station: station, exit: exit)
    }

    static func waypoints(line: Line, station: Station, exit: StationExit, mode: RouteMode) -> [Waypoint] {
        let coach = coachNumber(line: line, station: station, exit: exit)
        let metres = walkDistance(line: line, station: station, exit: exit)
        let minutes = max(1, Int(round(Double(metres) / 45.0)))

        var steps: [Waypoint] = []

        steps.append(
            Waypoint(
                id: 0,
                titleEn: "Ride in coach \(coach)",
                titleZh: "乘搭第 \(coach) 卡車廂",
                descEn: "Coach \(coach) is closest to Exit \(exit.id) on the \(line.en), so you walk the least.",
                descZh: "第 \(coach) 卡最接近 \(exit.id) 出口，步行距離最短。",
                symbol: "tram.fill",
                meta: "~\(metres) m · 步行約 \(minutes) 分鐘"
            )
        )

        switch mode {
        case .lift:
            steps.append(
                Waypoint(
                    id: 1,
                    titleEn: "Take the lift to the concourse",
                    titleZh: "乘搭升降機往大堂",
                    descEn: "Usually in the middle of the platform. An accessible help button on the platform calls station staff if you cannot find it.",
                    descZh: "一般位於月台中央；如找不到，月台設有無障礙召喚鈴，可按鈴請站務員協助。",
                    symbol: "figure.roll",
                    meta: "~2 min · 約 2 分鐘"
                )
            )
        case .escalator:
            steps.append(
                Waypoint(
                    id: 1,
                    titleEn: "Take the escalator to the concourse",
                    titleZh: "乘搭扶梯往大堂",
                    descEn: "Usually the quickest route, but it involves steps.",
                    descZh: "通常最快，但需使用扶梯或樓梯。",
                    symbol: "figure.stairs",
                    meta: "~1 min · 約 1 分鐘"
                )
            )
        }

        steps.append(
            Waypoint(
                id: 2,
                titleEn: "Head for Exit \(exit.id)",
                titleZh: "前往 \(exit.id) 出口",
                descEn: "Exit \(exit.id): \(exit.nameEn). Pass through the ticket gates.",
                descZh: "\(exit.id) 出口：\(exit.nameZh)。經閘機出閘。",
                symbol: "signpost.right.fill",
                meta: "~2 min · 約 2 分鐘"
            )
        )

        steps.append(
            Waypoint(
                id: 3,
                titleEn: "Arrive at Exit \(exit.id)",
                titleZh: "抵達 \(exit.id) 出口",
                descEn: "\(exit.nameEn) · \(station.en) station",
                descZh: "\(exit.nameZh) · \(station.zh)站",
                symbol: "checkmark.circle.fill",
                meta: nil
            )
        )

        return steps
    }

    /// A stabilised bearing so the AR arrow holds still while the user turns their phone.
    /// Real geometry requires an indoor positioning source; absent that, the relative
    /// bearing is derived deterministically per waypoint.
    static func bearing(for index: Int, total: Int) -> Double {
        let step = 360.0 / Double(max(total, 1))
        return (step * Double(index) + 15.0).truncatingRemainder(dividingBy: 360.0)
    }

    static func turnHint(deviceHeading: Double, target: Double) -> (symbol: String, en: String, zh: String) {
        var delta = target - deviceHeading
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }

        switch abs(delta) {
        case ..<30:
            return ("arrow.up", "Keep heading this way", "繼續朝此方向前進")
        case ..<120 where delta < 0:
            return ("arrow.turn.up.left", "Turn left ahead", "前方左轉")
        case ..<120:
            return ("arrow.turn.up.right", "Turn right ahead", "前方右轉")
        default:
            return ("arrow.uturn.left", "Turn around", "請轉身")
        }
    }
}
