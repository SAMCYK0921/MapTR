//
//  HeadingService.swift
//  MTR Lift Guide
//
//  Compass input for the AR overlay. Requests location permission for heading
//  updates only — no position is stored or transmitted.
//

import CoreLocation
import Foundation
import SwiftUI

final class HeadingService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var trueHeading: Double = 0
    @Published var isHeadingAvailable = false
    @Published var authorizationDenied = false

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 2
    }

    func request() {
        let status = manager.authorizationStatus
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdates()
        default:
            authorizationDenied = true
        }
    }

    private func startUpdates() {
        guard CLLocationManager.headingAvailable() else { return }
        isHeadingAvailable = true
        manager.startUpdatingHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdates()
        case .denied, .restricted:
            authorizationDenied = true
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        trueHeading = newHeading.trueHeading
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[Heading] \(error.localizedDescription)")
    }
}
