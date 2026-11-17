//
//  OfficialMaps.swift
//  MTR Lift Guide
//
//  Official MTR station guide PDFs (in-station maps), sourced from
//  https://www.mtr.com.hk/digitalleaflet — bundled so the maps work offline.
//

import Foundation
import PDFKit

enum OfficialMaps {

    private static var cached: [String: URL]?

    /// station id (MTR alias, e.g. "WHA") → official station guide PDF.
    static func mapping() -> [String: URL] {
        if let cached { return cached }
        let loaded: [String: URL] = {
            guard let url = Bundle.main.url(forResource: "official_maps", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let raw = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return raw.compactMapValues { URL(string: $0) }
        }()
        cached = loaded
        return loaded
    }

    static func url(for station: Station) -> URL? {
        mapping()[station.id]
    }
}

/// One station-layout page, extracted from the official guide so the card can
/// show exactly that page and size itself to the page's own aspect ratio.
struct StationMap {
    let document: PDFDocument
    let aspect: CGFloat
    let pageIndex: Int
}

/// Downloads, caches and digs out the station-layout page of each guide.
@MainActor
final class StationMapService: ObservableObject {

    private var cache: [String: StationMap] = [:]
    private var inFlight: [String: Task<StationMap?, Never>] = [:]

    func layout(for station: Station) async -> StationMap? {
        if let hit = cache[station.id] { return hit }
        guard let url = OfficialMaps.url(for: station) else { return nil }

        let key = station.id
        if let task = inFlight[key] { return await task.value }

        let task = Task<StationMap?, Never> {
            guard let data = try? await URLSession.shared.data(from: url).0,
                  let document = PDFDocument(data: data),
                  document.pageCount > 0
            else { return nil }

            let index = Self.layoutPageIndex(in: document)
            guard let page = document.page(at: index) else { return nil }

            let singlePage = PDFDocument()
            singlePage.insert(page, at: 0)

            let box = page.bounds(for: .mediaBox)
            let aspect = box.width > 0 ? box.height / box.width : 1.4
            return StationMap(document: singlePage, aspect: aspect, pageIndex: index)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let result { cache[key] = result }
        return result
    }

    /// Finds the "Station Layout" page; falls back to the second page,
    /// and to the only page when the guide has just one.
    private static func layoutPageIndex(in document: PDFDocument) -> Int {
        let keys = ["station layout", "stationlayout", "layout of station",
                    "車站佈置", "車站布置", "站內地圖", "站内地图", "平面圖", "平面图"]
        for index in 0..<document.pageCount {
            guard let text = document.page(at: index)?.string?.lowercased() else { continue }
            if keys.contains(where: { text.contains($0) }) { return index }
        }
        return min(1, document.pageCount - 1)
    }
}
