//
//  HomeView.swift
//  MTR Lift Guide
//
//  導航 Home — current station, official MTR in-station map, inline station
//  search, outdoor temperature and one-tap start. Liquid glass throughout.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var lang: Lang
    @EnvironmentObject private var network: Network
    @EnvironmentObject private var journey: JourneyStore
    @Binding var path: [Destination]
    let onStartAR: () -> Void

    @StateObject private var weather = WeatherService()
    @State private var query = ""

    private var station: Station? { journey.station(in: network) }
    private var exit: StationExit? { station.flatMap { journey.suggestedExit(for: $0) } }
    private var mode: RouteMode { station.map { journey.suggestedMode(for: $0) } ?? .lift }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return lang.t("早晨，準備好出發了嗎？", "Good morning — ready to go?")
        case 12..<18: return lang.t("午安，準備好出發了嗎？", "Good afternoon — ready to go?")
        default: return lang.t("晚安，準備好出發了嗎？", "Good evening — ready to go?")
        }
    }

    private var matches: [Station] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lowered = trimmed.lowercased()
        return network.stations.filter {
            $0.en.lowercased().contains(lowered)
                || $0.zh.contains(trimmed)
                || $0.id.lowercased().contains(lowered)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                searchSection
                if let station, let exit {
                    stationCard(station)
                    helpEntryCard(station)
                    destinationCard(station, exit)
                    StationMapCard(station: station, onLocate: onStartAR)
                    recentsRow(station)
                } else {
                    emptyCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(heroBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(Color.navPurple).frame(width: 8, height: 8)
                    Text(lang.t("站內導航", "In-station Navigation"))
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Color.navPurple)
                }
                Spacer()
                temperaturePill
                languageToggle
            }
            Text(greeting)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TitleBlock(
                zh: station != nil ? "你想從哪個出口離開？" : "你現在在哪個車站？",
                en: station != nil ? "Which exit are you leaving from?" : "Which station are you in?"
            )
        }
        .padding(.top, 16)
    }

    /// HKO outdoor temperature, glass pill, top-right.
    private var temperaturePill: some View {
        HStack(spacing: 5) {
            Image(systemName: "thermometer.sun")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.navPurple)
            Text(weather.temperatureC.map { "\($0)°C" } ?? "—")
                .font(.footnote.weight(.bold))
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassCapsule()
        .accessibilityLabel(Text(lang.t("室外溫度，香港天文台，\(weather.temperatureC.map(String.init) ?? "未知")度",
                                        "Outdoor temperature, Hong Kong Observatory, \(weather.temperatureC.map(String.init) ?? "unknown") degrees")))
    }

    private var languageToggle: some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy) { lang.code = lang.isChinese ? .en : .zh }
        } label: {
            Text(lang.toggleLabel)
                .font(.subheadline.weight(.bold))
                .monospaced()
                .foregroundStyle(Color.navPurple)
                .frame(width: 44, height: 32)
                .glassCapsuleButton()
        }
        .accessibilityLabel(Text(lang.t("切換至英文", "Switch to Chinese")))
    }

    // MARK: Inline station search

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(lang.t("搜尋車站…", "Search station…"), text: $query)
                    .font(.body)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .accessibilityLabel(Text(lang.t("搜尋車站", "Search station")))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel(Text(lang.t("清除搜尋", "Clear search")))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 50)
            .glassCapsule()

            if !matches.isEmpty {
                VStack(spacing: 2) {
                    ForEach(matches.prefix(6)) { station in
                        Button {
                            journey.setCurrentStation(station)
                            path.append(.exits(station))
                            query = ""
                        } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Color(hex: network.primaryLine(for: station)?.color ?? "9D1535"))
                                    .frame(width: 5, height: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(lang.t(station.zh, station.en))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(lang.t(station.en, station.zh))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.navPurple)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .glassSurface(cornerRadius: 22)
            }
        }
    }

    // MARK: Cards

    private func stationCard(_ station: Station) -> some View {
        Button {
            Haptics.tap()
            path.append(.stationPicker)
        } label: {
            HStack(spacing: 14) {
                Text(String(station.zh.prefix(1)))
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.navPurple, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.t("目前車站", "Current station"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(station.zh) \(station.en)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.navPurple)
                    .frame(width: 40, height: 40)
                    .background(Color.navPurpleSoft, in: Circle())
            }
            .padding(16)
            .glassSurface(cornerRadius: 24)
            .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(lang.t("更改車站，目前是\(station.zh)", "Change station, currently \(station.en)")))
    }

    private func helpEntryCard(_ station: Station) -> some View {
        Button {
            Haptics.tap()
            path.append(.helpBoard(station))
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Color.navPurple, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(lang.t("車站互助", "Station help"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(lang.t("求助，或幫助有需要嘅人", "Ask for help, or offer a hand"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .glassSurface(cornerRadius: 24)
            .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(lang.t("車站互助，求助或幫助他人", "Station help, ask for or offer help")))
    }

    private func destinationCard(_ station: Station, _ exit: StationExit) -> some View {
        let line = network.primaryLine(for: station)
        let estimate = line.map { RouteEngine.estimate(line: $0, station: station, exit: exit) }
        return VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(lang.t("前往 \(exit.id) 出口", "To Exit \(exit.id)"))
                        .font(.caption.weight(.heavy))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(Color.navPurple)
                    Text(lang.t(exit.nameZh, exit.nameEn))
                        .font(.title3.weight(.bold))
                    if let estimate {
                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                                .font(.caption)
                            Text(lang.t("約 \(estimate.minutes) 分鐘 · \(estimate.metres) 米",
                                        "~\(estimate.minutes) min · \(estimate.metres) m"))
                                .font(.footnote.weight(.semibold))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text(exit.id)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(
                        LinearGradient(colors: [Color.navPurple, Color.navPurpleDeep],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
                    .shadow(color: Color.navPurple.opacity(0.30), radius: 9, y: 4)
            }
            Button {
                Haptics.impact(.medium)
                path.append(.accessibility(station, exit))
            } label: {
                HStack(spacing: 8) {
                    Text(lang.t("開始導航", "Start navigation"))
                        .font(.body.weight(.bold))
                    Image(systemName: "arrow.right")
                        .font(.footnote.weight(.heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(colors: [Color.navPurple, Color.navPurpleDeep],
                                   startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .shadow(color: Color.navPurple.opacity(0.38), radius: 12, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(lang.t("先選擇電梯或扶梯", "Choose lift or escalator first")))
        }
        .padding(18)
        .glassSurface(cornerRadius: 26)
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [Color.navPurple.opacity(0.35), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        }
        .shadow(color: .black.opacity(0.06), radius: 16, y: 8)
    }

    private func recentsRow(_ station: Station) -> some View {
        let others = journey.recents.filter { $0.stationId != station.id }.prefix(4)
        guard !others.isEmpty else { return AnyView(EmptyView()) }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text(lang.t("最近路線", "Recent journeys"))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(others)) { recent in
                            recentChip(recent)
                        }
                    }
                }
            }
        )
    }

    private func recentChip(_ recent: RecentJourney) -> some View {
        Group {
            if let station = network.stations.first(where: { $0.id == recent.stationId }),
               let exit = station.exits.first(where: { $0.id == recent.exitId }) {
                Button {
                    path.append(.route(station, exit, recent.mode))
                } label: {
                    HStack(spacing: 8) {
                        Text(exit.id)
                            .font(.footnote.weight(.heavy))
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Color.navPurple, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(station.zh) \(station.en)")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(lang.t(recent.mode.titleZh, recent.mode.titleEn))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassCapsule()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyCard: some View {
        Button {
            path.append(.stationPicker)
        } label: {
            VStack(spacing: 14) {
                Image(systemName: "m.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.navPurple)
                Text(lang.t("先選擇你所在的車站", "Choose your station first"))
                    .font(.headline)
                Text(lang.t("輕按選擇", "Tap to choose"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .glassSurface(cornerRadius: 24)
            .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(lang.t("選擇車站", "Choose station")))
    }

    private var heroBackground: some View {
        ZStack {
            LinearGradient(colors: [.heroTop, .heroTop, .heroBottom],
                           startPoint: .top, endPoint: .bottom)
            // Soft brand-colour halos — gives the hero an "HDR" depth lift.
            RadialGradient(colors: [Color.navPurple.opacity(0.14), Color.navPurple.opacity(0)],
                           center: UnitPoint(x: 0.88, y: 0.06),
                           startRadius: 2, endRadius: 480)
            RadialGradient(colors: [Color.navPurple.opacity(0.08), Color.navPurple.opacity(0)],
                           center: UnitPoint(x: 0.08, y: 0.55),
                           startRadius: 2, endRadius: 420)
        }
    }
}

// MARK: - Schematic map preview (fallback when the official map is offline)

struct RouteMapView: View {
    let exitId: String
    let labels: [(zh: String, en: String)]
    let onLocate: () -> Void
    @EnvironmentObject private var lang: Lang

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let start = CGPoint(x: size.width * 0.16, y: size.height * 0.82)
            let end = CGPoint(x: size.width * 0.84, y: size.height * 0.18)
            let mid = CGPoint(x: size.width * 0.52, y: size.height * 0.55)

            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    var grid = Path()
                    for x in stride(from: 0.0, through: size.width, by: 36) {
                        grid.move(to: CGPoint(x: x, y: 0))
                        grid.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for y in stride(from: 0.0, through: size.height, by: 36) {
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(.navPurple.opacity(0.06)), lineWidth: 1)

                    var wide = Path()
                    wide.move(to: start)
                    wide.addQuadCurve(to: end, control: mid)
                    context.stroke(wide, with: .color(.navPurple.opacity(0.18)),
                                   style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    context.stroke(wide, with: .color(.navPurple),
                                   style: StrokeStyle(lineWidth: 6, lineCap: .round))
                }

                if labels.count > 0 {
                    chip(labels[0], at: CGPoint(x: size.width * 0.3, y: size.height * 0.72))
                }
                if labels.count > 1 {
                    chip(labels[1], at: CGPoint(x: size.width * 0.55, y: size.height * 0.45))
                }

                // Start marker
                Circle()
                    .fill(.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .overlay(Circle().fill(Color.navPurple).frame(width: 10, height: 10))
                    .position(start)

                // Exit badge
                Text(exitId)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.navPurple, in: Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .shadow(color: .navPurple.opacity(0.4), radius: 6, y: 3)
                    .position(end)

                // Floating buttons
                VStack(spacing: 10) {
                    Button(action: onLocate) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.navPurple)
                            .frame(width: 38, height: 38)
                            .glassSurface(cornerRadius: 19)
                    }
                    .accessibilityLabel(Text(lang.t("開始 AR 導航", "Start AR guidance")))

                    Image(systemName: "location.north.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .glassSurface(cornerRadius: 19)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.trailing, 12)
                .padding(.bottom, 14)
            }
        }
        .background(Color(.systemBackground).opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(lang.t("路線預覽圖", "Route preview")))
    }

    private func chip(_ label: (zh: String, en: String), at point: CGPoint) -> some View {
        Text(lang.t(label.zh, label.en))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            .position(point)
    }
}
