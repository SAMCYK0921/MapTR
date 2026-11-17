//
//  RouteView.swift
//  MTR Lift Guide
//
//  Step 4 — the step-by-step route as a localized timeline, recorded into Recents.
//

import SwiftUI

struct RouteView: View {
    @EnvironmentObject private var lang: Lang
    @EnvironmentObject private var network: Network
    @EnvironmentObject private var journey: JourneyStore
    let station: Station
    let exit: StationExit
    let mode: RouteMode
    @Binding var path: [Destination]

    @StateObject private var voice = VoiceService()

    private var line: Line? { network.primaryLine(for: station) }
    private var waypoints: [Waypoint] {
        guard let line else { return [] }
        return RouteEngine.waypoints(line: line, station: station, exit: exit, mode: mode)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    TitleBlock(zh: "你的路線", en: "Your route")
                    StepProgress(step: 3)
                }
                .padding(.vertical, 4)
            }

            Section {
                Timeline(waypoints: waypoints)
                    .padding(.vertical, 6)
            } header: {
                Text("\(lang.t(station.zh, station.en)) → \(lang.t("出口", "Exit")) \(exit.id) · \(lang.t(mode.titleZh, mode.titleEn))")
            }

            if let line {
                Section {
                    LineBadge(line: line)
                    Text(lang.t("\(line.coaches) 卡列車", "\(line.coaches)-car trains"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text(lang.t("路綫資料", "Line info"))
                }
            }
        }
        .listStyle(.insetGrouped)
        // Same reason as the tab bar: safeAreaInset makes the material compositing
        // pass paint a full-width rectangle. Overlay + explicit content padding instead.
        .safeAreaPadding(.bottom, 270)
        .overlay(alignment: .bottom) {
            ActionBar {
                Button {
                    voice.stop()
                    path.append(.guidance(station, exit, mode))
                } label: {
                    Text(lang.t("開始 AR 實景導航", "Start AR guidance"))
                }
                .buttonStyle(PrimaryButtonStyle())

                Button {
                    if voice.isSpeaking {
                        voice.stop()
                    } else {
                        voice.speakRoute(waypoints)
                    }
                } label: {
                    Label(voice.isSpeaking ? lang.t("停止語音導航", "Stop voice guidance")
                          : lang.t("語音導航", "Voice guidance"),
                          systemImage: voice.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                }
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .glassButton()

                Button(lang.t("更改出口", "Change exit")) {
                    guard path.count >= 2 else { path = []; return }
                    path.removeLast(2)
                }
                .font(.subheadline)
                .frame(height: 44)
            }
        }
        .navigationTitle(Text(lang.t("出口", "Exit") + " \(exit.id)"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { journey.record(station: station, exit: exit, mode: mode) }
        .onDisappear { voice.stop() }
    }
}

/// Numbered vertical timeline built from the waypoints.
private struct Timeline: View {
    @EnvironmentObject private var lang: Lang
    let waypoints: [Waypoint]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(waypoints.enumerated()), id: \.element.id) { index, wp in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(Color.navPurple)
                                .frame(width: 26, height: 26)
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        if index < waypoints.count - 1 {
                            Rectangle()
                                .fill(Color(.separator))
                                .frame(width: 2)
                                .frame(minHeight: 28)
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(lang.t(wp.titleZh, wp.titleEn))
                            .font(.subheadline.weight(.semibold))
                        Text(lang.t(wp.descZh, wp.descEn))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let meta = wp.meta {
                            Text(meta)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, index < waypoints.count - 1 ? 18 : 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}
