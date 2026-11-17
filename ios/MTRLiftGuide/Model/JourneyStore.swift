//
//  JourneyStore.swift
//  MTR Lift Guide
//
//  Persists the current station and recent journeys so the home screen can
//  offer one-tap access to the route you use most.
//

import Foundation
import SwiftUI

struct RecentJourney: Codable, Identifiable, Hashable {
    let stationId: String
    let exitId: String
    let modeRaw: String
    let date: Date

    var id: String { "\(stationId)-\(exitId)-\(modeRaw)" }
    var mode: RouteMode { RouteMode(rawValue: modeRaw) ?? .lift }
}

final class JourneyStore: ObservableObject {

    @Published var currentStationId: String? {
        didSet { persist() }
    }

    @Published var recents: [RecentJourney] = [] {
        didSet { persist() }
    }

    private let defaults: UserDefaults
    private static let stationKey = "journey.currentStation"
    private static let recentsKey = "journey.recents"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        currentStationId = defaults.string(forKey: Self.stationKey)
        if let data = defaults.data(forKey: Self.recentsKey),
           let list = try? JSONDecoder().decode([RecentJourney].self, from: data) {
            recents = list
        }
    }

    private func persist() {
        defaults.set(currentStationId, forKey: Self.stationKey)
        if let data = try? JSONEncoder().encode(recents) {
            defaults.set(data, forKey: Self.recentsKey)
        }
    }

    func setCurrentStation(_ station: Station) {
        currentStationId = station.id
    }

    func record(station: Station, exit: StationExit, mode: RouteMode) {
        let entry = RecentJourney(stationId: station.id, exitId: exit.id,
                                  modeRaw: mode.rawValue, date: Date())
        recents.removeAll { $0.id == entry.id }
        recents.insert(entry, at: 0)
        if recents.count > 20 {
            recents.removeLast(recents.count - 20)
        }
    }

    func station(in network: Network) -> Station? {
        guard let id = currentStationId else { return nil }
        return network.stations.first { $0.id == id }
    }

    /// The exit most recently used at the given station, else its first exit.
    func suggestedExit(for station: Station) -> StationExit? {
        if let recent = recents.first(where: { $0.stationId == station.id }) {
            return station.exits.first { $0.id == recent.exitId }
        }
        return station.exits.first
    }

    func suggestedMode(for station: Station) -> RouteMode {
        recents.first(where: { $0.stationId == station.id })?.mode ?? .lift
    }

    /// The most recent journey, fully resolved against the network.
    func lastJourney(in network: Network) -> (Station, StationExit, RouteMode)? {
        for recent in recents {
            guard let station = network.stations.first(where: { $0.id == recent.stationId }),
                  let exit = station.exits.first(where: { $0.id == recent.exitId }) else { continue }
            return (station, exit, recent.mode)
        }
        return nil
    }
}
