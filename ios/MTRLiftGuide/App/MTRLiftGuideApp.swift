//
//  MTRLiftGuideApp.swift
//  MTR Lift Guide
//

import SwiftUI

@main
struct MTRLiftGuideApp: App {
    @StateObject private var network = (try? Network.load()) ?? Network(file: NetworkFile(
        meta: NetworkMeta(
            version: "—",
            source: "—",
            provenanceNote: "Missing dataset",
            disclaimerEn: "Dataset missing from bundle.",
            disclaimerZh: "應用程式缺少車站資料。"
        ),
        lines: [],
        stations: []
    ))
    @StateObject private var lang = Lang()
    @StateObject private var journey = JourneyStore()
    @StateObject private var help = HelpStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(network)
                .environmentObject(lang)
                .environmentObject(journey)
                .environmentObject(help)
                .tint(Color.navPurple)
        }
    }
}
