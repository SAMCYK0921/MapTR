//
//  ARGuidanceView.swift
//  MTR Lift Guide
//
//  Step 5 — AR guidance: an ARKit session anchors a RealityKit arrow on the
//  floor or wall in front of the user, pointing at the current waypoint
//  bearing, with a card, spoken guidance and Dynamic Island updates on top.
//  Devices without world tracking fall back to the plain camera feed.
//

import ARKit
import SwiftUI
import UIKit

struct ARGuidanceView: View {
    @EnvironmentObject private var lang: Lang
    @EnvironmentObject private var network: Network
    let station: Station
    let exit: StationExit
    let mode: RouteMode
    let embedded: Bool
    let onFinish: () -> Void

    @StateObject private var camera = CameraModel()
    @StateObject private var arGuide = ARGuideController()
    @StateObject private var heading = HeadingService()
    @StateObject private var voice = VoiceService()
    @State private var index = 0
    @State private var lastDirectionSymbol = ""

    /// World tracking needs a real sensor stack; the simulator falls back to the
    /// plain camera feed with the compass overlay.
    private var supportsAR: Bool { ARWorldTrackingConfiguration.isSupported }

    private var waypoints: [Waypoint] {
        guard let line = network.primaryLine(for: station) else { return [] }
        return RouteEngine.waypoints(line: line, station: station, exit: exit, mode: mode)
    }

    private var current: Waypoint? {
        waypoints.indices.contains(index) ? waypoints[index] : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if supportsAR {
                // ARKit-backed scene: the arrow is anchored on the real floor
                // or wall in front of the user.
                ARGuidanceScene(guide: arGuide)
                    .ignoresSafeArea()
                if let failure = arGuide.failure {
                    failureBanner(failure)
                }
            } else {
                // Always mount the camera preview so its controller starts the session;
                // show a status overlay on top while it boots or fails.
                CameraPreview(model: camera)
                    .ignoresSafeArea()

                if !camera.isRunning {
                    cameraBanner
                }
            }

            overlay
        }
        .navigationTitle(Text(lang.t("AR 實景導航", "AR guidance")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            heading.request()
            startLiveActivity()
            arGuide.setTarget(bearing: target)
            arGuide.setHeading(heading.trueHeading, available: heading.isHeadingAvailable)
        }
        .onAppear { speakCurrent() }
        .onChange(of: index) {
            speakCurrent()
            updateLiveActivity()
            arGuide.setTarget(bearing: target)
        }
        .onChange(of: heading.trueHeading) { _ in
            updateDirectionInLiveActivity()
            arGuide.setHeading(heading.trueHeading, available: heading.isHeadingAvailable)
        }
        // Compass permission can arrive after the screen appears; without this
        // the AR arrow would never learn that heading input became available.
        .onChange(of: heading.isHeadingAvailable) { _, available in
            arGuide.setHeading(heading.trueHeading, available: available)
        }
        .onDisappear {
            camera.stop()
            arGuide.stop()
            voice.stop()
            GuidanceActivity.shared.end()
        }
    }

    // MARK: - Overlay

    private var overlay: some View {
        VStack {
            progressPill
                .padding(.top, 8)
            if supportsAR, arGuide.failure == nil, arGuide.status == .searching {
                arHintPill
                    .padding(.top, 6)
            }
            Spacer()
            if let current {
                waypointCard(current)
            }
            controls
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var progressPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text("\(min(index + 1, waypoints.count)) / \(waypoints.count) · \(lang.t(station.zh, station.en)) → \(lang.t("出口", "Exit")) \(exit.id)")
                .font(.caption.weight(.semibold))
            if case .placed(let alignment) = arGuide.status {
                Text(alignment == .floor
                     ? lang.t("AR · 地面", "AR · floor")
                     : lang.t("AR · 牆身", "AR · wall"))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(red: 0.98, green: 0.35, blue: 0.42))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassSurface(cornerRadius: 20, tint: .black)
    }

    /// Shown while the session is still looking for a surface to anchor onto.
    private var arHintPill: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .tint(.white)
            Text(lang.t("將手機對準地面或牆身，箭頭會投射到現場",
                        "Point at the floor or a wall — the arrow lands in the scene"))
                .font(.caption.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 18, tint: .black)
    }

    private func waypointCard(_ wp: Waypoint) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: hint.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .rotationEffect(.degrees(-(heading.trueHeading - target)))
                    .animation(.easeOut(duration: 0.25), value: heading.trueHeading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.t(wp.titleZh, wp.titleEn))
                        .font(.headline)
                    Text(lang.t(hint.zh, hint.en))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider().opacity(0.4)
            Text(lang.t(wp.descZh, wp.descEn))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let meta = wp.meta {
                Text(meta)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .glassSurface(cornerRadius: 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    advance()
                } label: {
                    Text(index < waypoints.count - 1
                         ? lang.t("下一指示", "Next waypoint")
                         : lang.t("抵達出口", "Arrived"))
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: .infinity)

                if supportsAR {
                    Button {
                        Haptics.selection()
                        arGuide.recenter()
                    } label: {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .frame(width: 56, height: 54)
                    .glassButton()
                    .accessibilityLabel(Text(lang.t("重新掃描", "Rescan surface")))
                }

                Button {
                    restartJourney()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 18, weight: .semibold))
                }
                .frame(width: 56, height: 54)
                .glassButton()
                .accessibilityLabel(Text(lang.t("重新開始", "Restart")))
            }

            Button {
                if voice.isSpeaking { voice.stop() } else { speakCurrent() }
            } label: {
                Label(voice.isSpeaking ? lang.t("停止語音", "Stop voice")
                      : lang.t("重播語音", "Repeat voice"),
                      systemImage: voice.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(height: 44)
            .glassButton(cornerRadius: 16)
        }
    }

    // MARK: - Helpers

    private var statusMessage: String {
        switch camera.failure {
        case .denied:
            return lang.t("相機權限未開啟，請在設定中允許使用相機。",
                          "Camera access is off. Please allow camera access in Settings.")
        case .unavailable:
            return lang.t("此裝置沒有可用的後置鏡頭。", "No rear camera is available on this device.")
        case .none:
            return lang.t("正在啓動相機…", "Starting camera…")
        }
    }

    // MARK: - Status banners

    private var cameraBanner: some View {
        VStack(spacing: 14) {
            Image(systemName: camera.failure == nil ? "camera.viewfinder"
                  : (camera.failure == .denied ? "camera.badge.ellipsis" : "camera.slash"))
                .font(.system(size: 34))
            Text(statusMessage)
                .font(.footnote)
                .multilineTextAlignment(.center)
            if camera.failure == .denied {
                Button {
                    openSettings()
                } label: {
                    Label(lang.t("開啟設定", "Open Settings"),
                          systemImage: "gear")
                }
                .glassButton(cornerRadius: 16)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 32)
    }

    private func failureBanner(_ failure: ARGuideController.Failure) -> some View {
        VStack(spacing: 14) {
            Image(systemName: failureSymbol(failure))
                .font(.system(size: 34))
            Text(failureMessage(failure))
                .font(.footnote)
                .multilineTextAlignment(.center)
            if failure == .cameraDenied {
                Button {
                    openSettings()
                } label: {
                    Label(lang.t("開啟設定", "Open Settings"),
                          systemImage: "gear")
                }
                .glassButton(cornerRadius: 16)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 32)
    }

    private func failureSymbol(_ failure: ARGuideController.Failure) -> String {
        switch failure {
        case .unsupported: return "arkit"
        case .cameraDenied: return "camera.badge.ellipsis"
        case .interrupted: return "exclamationmark.triangle"
        }
    }

    private func failureMessage(_ failure: ARGuideController.Failure) -> String {
        switch failure {
        case .unsupported:
            return lang.t("此裝置不支援 AR 世界追蹤，已切換為相機指示模式。",
                          "AR world tracking is unavailable on this device. Showing the camera view instead.")
        case .cameraDenied:
            return lang.t("相機權限未開啟，AR 無法啟動。請在設定中允許使用相機。",
                          "AR needs the camera. Please allow camera access in Settings.")
        case .interrupted(let reason):
            return lang.t("AR 追蹤中斷，請重新掃描。", "AR tracking was interrupted. Please rescan.")
                + "\n" + reason
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var target: Double {
        RouteEngine.bearing(for: index, total: waypoints.count)
    }

    private var hint: (symbol: String, en: String, zh: String) {
        guard heading.isHeadingAvailable else {
            return ("arrow.up", "Follow the instruction below", "根據下方指示前行")
        }
        return RouteEngine.turnHint(deviceHeading: heading.trueHeading, target: target)
    }

    private func speakCurrent() {
        guard let current else { return }
        voice.speak(current.titleZh + "。" + current.descZh,
                    current.titleEn + ". " + current.descEn)
    }

    // MARK: - Live Activity (Dynamic Island)

    /// Full step list shown on the expanded island, already localized.
    private var stepItems: [GuidanceStep] {
        waypoints.map { GuidanceStep(title: lang.t($0.titleZh, $0.titleEn), symbol: $0.symbol) }
    }

    /// Compass direction relative to the target bearing.
    private var direction: (symbol: String, text: String) {
        guard heading.isHeadingAvailable else {
            return ("arrow.up", lang.t("跟隨下方指示", "Follow directions"))
        }
        let h = RouteEngine.turnHint(deviceHeading: heading.trueHeading, target: target)
        return (h.symbol, lang.t(h.zh, h.en))
    }

    /// Travel mode (lift vs escalator/stairs).
    private var modeInfo: (symbol: String, title: String) {
        (mode.symbol, lang.t(mode.titleZh, mode.titleEn))
    }

    private func liveActivityState() -> GuidanceActivityAttributes.ContentState? {
        guard let current else { return nil }
        return GuidanceActivityAttributes.ContentState(
            stepIndex: index,
            totalSteps: waypoints.count,
            stepTitle: lang.t(current.titleZh, current.titleEn),
            hint: lang.t(hint.zh, hint.en),
            directionSymbol: direction.symbol,
            directionText: direction.text,
            modeSymbol: modeInfo.symbol,
            modeTitle: modeInfo.title,
            steps: stepItems
        )
    }

    private func startLiveActivity() {
        guard let state = liveActivityState() else { return }
        GuidanceActivity.shared.start(
            stationName: lang.t(station.zh, station.en),
            exitID: exit.id,
            state: state)
    }

    private func updateLiveActivity() {
        guard let state = liveActivityState() else { return }
        GuidanceActivity.shared.update(state: state)
    }

    /// Updates the island only when the compass classification actually changes,
    /// so we don't spam ActivityKit on every tiny heading tick.
    private func updateDirectionInLiveActivity() {
        let symbol = direction.symbol
        guard symbol != lastDirectionSymbol else { return }
        lastDirectionSymbol = symbol
        updateLiveActivity()
    }

    private func advance() {
        guard current != nil else { return }
        if index < waypoints.count - 1 {
            Haptics.impact(.medium)
            index += 1
        } else {
            // Journey complete — dismiss the island immediately.
            Haptics.success()
            GuidanceActivity.shared.end()
            restartJourney()
        }
    }

    private func restartJourney() {
        camera.stop()
        arGuide.stop()
        voice.stop()
        onFinish()
    }
}
