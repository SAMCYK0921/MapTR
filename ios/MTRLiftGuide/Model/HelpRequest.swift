//
//  HelpRequest.swift
//  MTR Lift Guide
//
//  In-station mutual-aid board: "seeking for help" / "offering help".
//  A request is shown as a floating bubble on the station help board; a double
//  tap pops the bubble and opens a chat + precise in-station location card.
//

import Foundation
import SwiftUI

// MARK: - Kind of help

enum HelpKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case findExit            // help me find my exit
    case visualImpairment    // guide a visually impaired traveller
    case mobility            // support someone with limited mobility
    case other               // anything else

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .findExit: return "signpost.right.fill"
        case .visualImpairment: return "eye.slash.fill"
        case .mobility: return "figure.roll"
        case .other: return "hand.raised.fill"
        }
    }

    var titleZh: String {
        switch self {
        case .findExit: return "幫我找出口"
        case .visualImpairment: return "視障人士需要攙扶"
        case .mobility: return "腿腳不便需要攙扶"
        case .other: return "其他協助"
        }
    }

    var titleEn: String {
        switch self {
        case .findExit: return "Help me find my exit"
        case .visualImpairment: return "Visually impaired — need a guide"
        case .mobility: return "Mobility support needed"
        case .other: return "Other assistance"
        }
    }

    /// Short label printed inside the bubble.
    var shortZh: String {
        switch self {
        case .findExit: return "找出口"
        case .visualImpairment: return "視障"
        case .mobility: return "腿腳"
        case .other: return "協助"
        }
    }

    var shortEn: String {
        switch self {
        case .findExit: return "Exit"
        case .visualImpairment: return "Visual"
        case .mobility: return "Mobility"
        case .other: return "Help"
        }
    }

    /// Bubble tint.
    var tint: Color {
        switch self {
        case .findExit: return Color(red: 0.89, green: 0.12, blue: 0.14)     // MTR red
        case .visualImpairment: return Color(red: 0.33, green: 0.31, blue: 0.82) // indigo
        case .mobility: return Color(red: 0.10, green: 0.58, blue: 0.45)      // teal
        case .other: return Color(red: 0.72, green: 0.48, blue: 0.10)         // amber
        }
    }
}

// MARK: - Approximate in-station spot

enum HelpSpot: String, Codable, CaseIterable, Identifiable, Hashable {
    case concourse
    case platform
    case ticketHall
    case nearExit

    var id: String { rawValue }

    var titleZh: String {
        switch self {
        case .concourse: return "大堂"
        case .platform: return "月台"
        case .ticketHall: return "售票大堂"
        case .nearExit: return "出口附近"
        }
    }

    var titleEn: String {
        switch self {
        case .concourse: return "Concourse"
        case .platform: return "Platform"
        case .ticketHall: return "Ticket hall"
        case .nearExit: return "Near exit"
        }
    }

    /// Normalized (0...1) position on the schematic station map.
    var point: CGPoint {
        switch self {
        case .concourse: return CGPoint(x: 0.46, y: 0.40)
        case .platform: return CGPoint(x: 0.28, y: 0.76)
        case .ticketHall: return CGPoint(x: 0.68, y: 0.28)
        case .nearExit: return CGPoint(x: 0.82, y: 0.60)
        }
    }
}

// MARK: - Status

enum HelpStatus: String, Codable, Hashable {
    case open
    case claimed
    case completed
}

// MARK: - Request

struct HelpRequest: Identifiable, Codable, Hashable {
    let id: UUID
    let stationId: String
    var kind: HelpKind
    var targetExitId: String?
    var spot: HelpSpot
    var note: String
    var requesterName: String
    var createdAt: Date
    var status: HelpStatus
    /// Stable 0...1 value used to scatter bubbles on the board.
    var offsetSeed: Double
    /// True when auto-generated as a demo request (refreshed on each visit).
    var isSample: Bool?

    init(id: UUID = UUID(),
         stationId: String,
         kind: HelpKind,
         targetExitId: String? = nil,
         spot: HelpSpot,
         note: String,
         requesterName: String,
         status: HelpStatus = .open,
         offsetSeed: Double = Double.random(in: 0...1),
         isSample: Bool? = nil,
         createdAt: Date = Date()) {
        self.id = id
        self.stationId = stationId
        self.kind = kind
        self.targetExitId = targetExitId
        self.spot = spot
        self.note = note
        self.requesterName = requesterName
        self.status = status
        self.offsetSeed = offsetSeed
        self.isSample = isSample
        self.createdAt = createdAt
    }

    var isOpen: Bool { status == .open }
}

// MARK: - Store

final class HelpStore: ObservableObject {

    @Published var requests: [HelpRequest] = [] {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private static let key = "help.requests"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let list = try? JSONDecoder().decode([HelpRequest].self, from: data) {
            requests = list
        }
    }

    func requests(for stationId: String, includeResolved: Bool = false) -> [HelpRequest] {
        requests.filter {
            $0.stationId == stationId && (includeResolved || $0.isOpen)
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    func request(id: UUID) -> HelpRequest? {
        requests.first { $0.id == id }
    }

    func add(_ request: HelpRequest) {
        requests.append(request)
    }

    func claim(_ id: UUID) {
        update(id) { $0.status = .claimed }
    }

    func complete(_ id: UUID) {
        update(id) { $0.status = .completed }
    }

    func remove(_ id: UUID) {
        requests.removeAll { $0.id == id }
    }

    private func update(_ id: UUID, _ body: (inout HelpRequest) -> Void) {
        guard let index = requests.firstIndex(where: { $0.id == id }) else { return }
        body(&requests[index])
    }

    /// Re-randomises demo requests every time a station board is opened, so the
    /// same station never greets you with an identical set twice. Requests the
    /// user posts themselves are preserved.
    func refreshSamples(for station: Station, lang: Lang) {
        // Clear all previous samples for this station (handled ones included).
        requests.removeAll { $0.stationId == station.id && ($0.isSample ?? false) }

        let count = Int.random(in: 2...4)
        let names = ["阿明", "陳婆婆", "Ken", "黃小姐", "阿俊", "李伯", "May",
                     "阿豪", "張太", "Sam", "周先生", "阿玲", "Ryan", "何太"]
        let notes: [(zh: String, en: String)] = [
            ("第一次嚟呢個站，唔知點行去出口。", "First time here — not sure how to reach the exit."),
            ("長者行動不便，想有人扶我上月台。", "An elderly traveller needs a hand to the platform."),
            ("視力唔好，想有人帶我行去閘口。", "Low vision — could someone guide me to the gates?"),
            ("拎住好多行李，想幫手搵升降機。", "Carrying heavy luggage, need help finding the lift."),
            ("輪椅使用者，想知邊個出口有升降機。", "Wheelchair user — which exit has a lift?"),
            ("趕時間，想快啲搵到最近嘅出口。", "In a hurry — need the nearest exit."),
            ("同小朋友一齊，想有人指路。", "Travelling with a child, need directions."),
            ("聽障人士，想用文字溝通問路。", "Deaf traveller — prefer to ask by text.")
        ]

        let kinds = HelpKind.allCases
        let spots = HelpSpot.allCases

        for _ in 0..<count {
            let kind = kinds.randomElement() ?? .findExit
            let spot = spots.randomElement() ?? .concourse
            let note = notes.randomElement()!
            let name = names.randomElement() ?? "路人"
            let exitId = kind == .findExit ? station.exits.randomElement()?.id : nil
            requests.append(
                HelpRequest(stationId: station.id,
                            kind: kind,
                            targetExitId: exitId,
                            spot: spot,
                            note: lang.t(note.zh, note.en),
                            requesterName: name,
                            isSample: true)
            )
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(requests) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
