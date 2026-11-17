//
//  MTRData.swift
//  MTR Lift Guide
//
//  Codable model + loader for the bundled network dataset (`stations.json`).
//

import Foundation

// MARK: - Raw (JSON mirror)

struct Line: Codable, Identifiable, Hashable {
    let id: String
    let en: String
    let zh: String
    let color: String
    let coaches: Int
}

struct ExitInfo: Codable, Hashable {
    let en: String
    let zh: String
}

struct Note: Codable, Hashable {
    let en: String
    let zh: String
}

struct RawStation: Codable, Identifiable {
    let id: String
    let en: String
    let zh: String
    let lines: [String]
    let exits: [String]
    let exitInfo: [String: ExitInfo]?
    let note: Note?
    let verified: Bool?
}

struct NetworkMeta: Codable {
    let version: String
    let source: String
    let provenanceNote: String
    let disclaimerEn: String
    let disclaimerZh: String
}

struct NetworkFile: Codable {
    let meta: NetworkMeta
    let lines: [Line]
    let stations: [RawStation]
}

// MARK: - Resolved models

struct StationExit: Identifiable, Hashable, Codable {
    let id: String
    let nameEn: String
    let nameZh: String
    let verified: Bool

    var display: String { "Exit \(id) · \(id) 出口" }
}

struct Station: Identifiable, Hashable, Codable {
    let id: String
    let en: String
    let zh: String
    let lineIds: [String]
    let exits: [StationExit]
    let note: Note?
    let verified: Bool

    var title: String { "\(en) \(zh)" }
}

enum RouteMode: String, CaseIterable, Identifiable, Hashable {
    case lift
    case escalator

    var id: String { rawValue }

    var titleEn: String {
        switch self {
        case .lift: return "Lift all the way"
        case .escalator: return "Escalator or stairs"
        }
    }

    var titleZh: String {
        switch self {
        case .lift: return "全程電梯"
        case .escalator: return "扶梯或樓梯"
        }
    }

    var symbol: String {
        switch self {
        case .lift: return "figure.roll.latex"
        case .escalator: return "figure.stairs"
        }
    }

    var descEn: String {
        switch self {
        case .lift: return "Step-free using station lifts."
        case .escalator: return "Usually quickest, but involves steps or stairs."
        }
    }

    var descZh: String {
        switch self {
        case .lift: return "使用站內升降機，全程無障礙。"
        case .escalator: return "通常最快，但需步級或樓梯。"
        }
    }
}

struct Waypoint: Identifiable, Hashable {
    let id: Int
    let titleEn: String
    let titleZh: String
    let descEn: String
    let descZh: String
    let symbol: String
    let meta: String?
}

// MARK: - Loader

enum NetworkError: LocalizedError {
    case missingResource

    var errorDescription: String? {
        "The bundled station dataset could not be found in the app bundle."
    }
}

final class Network: ObservableObject {
    let meta: NetworkMeta
    let lines: [Line]
    let stations: [Station]
    private let lineIndex: [String: Line]

    init(file: NetworkFile) {
        self.meta = file.meta
        self.lines = file.lines
        self.lineIndex = Dictionary(uniqueKeysWithValues: file.lines.map { ($0.id, $0) })

        self.stations = file.stations.map { raw in
            let exits: [StationExit] = raw.exits.map { letter in
                let info = raw.exitInfo?[letter]
                return StationExit(
                    id: letter,
                    nameEn: info?.en ?? "Exit \(letter)",
                    nameZh: info?.zh ?? "\(letter) 出口",
                    verified: raw.exitInfo?[letter] != nil
                )
            }
            return Station(
                id: raw.id,
                en: raw.en,
                zh: raw.zh,
                lineIds: raw.lines,
                exits: exits,
                note: raw.note,
                verified: raw.verified ?? false
            )
        }
    }

    static func load() throws -> Network {
        guard let url = Bundle.main.url(forResource: "stations", withExtension: "json") else {
            throw NetworkError.missingResource
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let file = try decoder.decode(NetworkFile.self, from: data)
        return Network(file: file)
    }

    func line(_ id: String) -> Line? { lineIndex[id] }

    func lines(for station: Station) -> [Line] {
        station.lineIds.compactMap { lineIndex[$0] }
    }

    /// Line used for platform/coach guidance — the first line with the most cars, else the first line.
    func primaryLine(for station: Station) -> Line? {
        lines(for: station).sorted { $0.coaches > $1.coaches }.first
    }
}
