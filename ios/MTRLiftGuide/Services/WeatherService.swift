//
//  WeatherService.swift
//  MTR Lift Guide
//
//  Outdoor temperature from the Hong Kong Observatory open data API
//  (official source, no key required). Refreshes every 15 minutes.
//

import Foundation
import Combine

@MainActor
final class WeatherService: ObservableObject {

    @Published var temperatureC: Int?
    @Published var isFresh = false

    private let session: URLSession
    private var cancellables = Set<AnyCancellable>()
    private var lastFetch: Date?

    private static let apiURL = URL(string:
        "https://data.weather.gov.hk/weatherAPI/opendata/weather.php?dataType=rhrread&lang=en")!

    init(session: URLSession = .shared) {
        self.session = session
        refresh()
        Timer.publish(every: 900, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func refresh() {
        session.dataTask(with: Self.apiURL) { [weak self] data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let temperature = json["temperature"] as? [String: Any],
                  let records = temperature["data"] as? [[String: Any]] else { return }

            let preferred = records.first { ($0["place"] as? String) == "Hong Kong Observatory" }
                ?? records.first
            guard let value = preferred?["value"] as? Int else { return }

            Task { @MainActor [weak self] in
                self?.temperatureC = value
                self?.lastFetch = Date()
                self?.isFresh = true
            }
        }.resume()
    }
}
