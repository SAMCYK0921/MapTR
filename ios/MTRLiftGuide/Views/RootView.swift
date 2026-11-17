//
//  RootView.swift
//  MTR Lift Guide
//
//  Tab-based shell: 導航 Home / 車站 Stations / (AR centre button) / 最近 Recents / 更多 More,
//  with a floating liquid-glass tab bar and a full-screen AR cover.
//

import SwiftUI

// MARK: - Design tokens (reference style: violet over mint)

extension Color {
    static let navPurple = Color.dynamic(light: "060931", dark: "E31E24")
    static let navPurpleDeep = Color.dynamic(light: "1B1F63", dark: "E31E24")
    static let navPurpleSoft = Color.dynamic(light: "E5E6F1", dark: "2A2B45")
    static let heroTop = Color.dynamic(light: "EAEBF4", dark: "191924")
    static let heroBottom = Color.dynamic(light: "E4EFEA", dark: "14161D")
}

// MARK: - Destinations

enum Destination: Hashable {
    case stationPicker
    case exits(Station)
    case accessibility(Station, StationExit)
    case route(Station, StationExit, RouteMode)
    case guidance(Station, StationExit, RouteMode)
    case helpBoard(Station)
}

struct ARJourney: Identifiable, Hashable {
    let station: Station
    let exit: StationExit
    let mode: RouteMode
    var id: String { "\(station.id)-\(exit.id)-\(mode.rawValue)" }
}

/// Registers the shared navigation destinations on any stack.
struct Destinations: ViewModifier {
    @Binding var path: [Destination]

    func body(content: Content) -> some View {
        content.navigationDestination(for: Destination.self) { destination in
            switch destination {
            case .stationPicker:
                StationListView(mode: .picker, path: $path)
            case .exits(let station):
                ExitListView(station: station, path: $path)
            case .accessibility(let station, let exit):
                AccessibilityView(station: station, exit: exit, path: $path)
            case .route(let station, let exit, let mode):
                RouteView(station: station, exit: exit, mode: mode, path: $path)
            case .guidance(let station, let exit, let mode):
                ARGuidanceView(station: station, exit: exit, mode: mode,
                               embedded: true, onFinish: { path.removeAll() })
            case .helpBoard(let station):
                HelpBoardView(station: station, path: $path)
            }
        }
    }
}

// MARK: - Root

enum Tab: Hashable {
    case home, stations, recents, more
}

/// iOS 26 draws a translucent "scroll edge effect" band along the bottom of every
/// scroll view. With a custom floating tab bar that band reads as an extra
/// full-width rectangle behind the capsule, so it is switched off.
private struct HideBottomScrollEdgeEffect: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .bottom)
        } else {
            content
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var lang: Lang
    @EnvironmentObject private var network: Network
    @EnvironmentObject private var journey: JourneyStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var tab: Tab = .home
    @Namespace private var tabNamespace
    @State private var homePath: [Destination] = []
    @State private var stationsPath: [Destination] = []
    @State private var recentsPath: [Destination] = []
    @State private var morePath: [Destination] = []
    @State private var arJourney: ARJourney?

    var body: some View {
        Group {
            switch tab {
            case .home:
                stack(path: $homePath) { HomeView(path: $homePath, onStartAR: startAR) }
            case .stations:
                stack(path: $stationsPath) {
                    StationListView(mode: .tab, path: $stationsPath)
                }
            case .recents:
                stack(path: $recentsPath) { RecentsView(path: $recentsPath, onStartAR: startAR) }
            case .more:
                stack(path: $morePath) { MoreView() }
            }
        }
        // Overlay instead of safeAreaInset: safe-area insets are composited as part of the
        // material/glass pass on iOS 26, which paints an extra full-width rectangle behind
        // the capsule tab bar.
        .modifier(HideBottomScrollEdgeEffect())
        .overlay(alignment: .bottom) {
            if showsTabBar {
                tabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: showsTabBar)
        .ignoresSafeArea(.keyboard)
        .fullScreenCover(item: $arJourney) { journey in
            ARGuidanceView(station: journey.station, exit: journey.exit, mode: journey.mode,
                           embedded: false, onFinish: { arJourney = nil })
        }
    }

    private func stack<Content: View>(path: Binding<[Destination]>,
                                      @ViewBuilder content: () -> Content) -> some View {
        NavigationStack(path: path) {
            content()
                .modifier(Destinations(path: path))
        }
    }

    // MARK: AR entry

    private func startAR() {
        if let (station, exit, mode) = journey.lastJourney(in: network) {
            arJourney = ARJourney(station: station, exit: exit, mode: mode)
        } else if let station = journey.station(in: network),
                  let exit = journey.suggestedExit(for: station) {
            arJourney = ARJourney(station: station, exit: exit,
                                  mode: journey.suggestedMode(for: station))
        } else {
            tab = .stations
        }
    }

    // MARK: Tab bar

    /// The AR guidance screen runs full-bleed, so the floating tab bar gets out of the way
    /// whenever a `.guidance` destination is on any tab's navigation stack.
    private var showsTabBar: Bool {
        !([homePath, stationsPath, recentsPath, morePath].contains { path in
            path.contains { destination in
                if case .guidance = destination { return true }
                return false
            }
        })
    }

    private var isDark: Bool { colorScheme == .dark }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(.home, symbol: "map.fill", zh: "導航", en: "Navigate")
            tabButton(.stations, symbol: "m.circle.fill", zh: "車站", en: "Stations")
            departButton
            tabButton(.recents, symbol: "clock.fill", zh: "最近", en: "Recent")
            tabButton(.more, symbol: "ellipsis", zh: "更多", en: "More")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            (isDark ? Color.white.opacity(0.03) : Color.white.opacity(0.10))
                .glassCapsule(tint: isDark ? Color.white.opacity(0.10) : Color.white.opacity(0.50))
        }
        // Clip the glass/material paint region to the capsule itself so it cannot
        // bleed into the parent container, then draw the shadow outside that shape.
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func tabButton(_ value: Tab, symbol: String, zh: String, en: String) -> some View {
        let selected = tab == value
        return Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { tab = value }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                Text(lang.t(zh, en))
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selected ? Color.navPurple : Color(.secondaryLabel))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background {
                if selected {
                    Capsule()
                        .fill(isDark ? Color.white.opacity(0.05) : Color.white.opacity(0.02))
                        .glassCapsuleButton(tint: isDark ? Color.white.opacity(0.16) : Color.white.opacity(0.35))
                        .overlay {
                            Capsule().strokeBorder(isDark ? Color.white.opacity(0.20) : Color.white.opacity(0.45), lineWidth: 1)
                        }
                        .matchedGeometryEffect(id: "tab-highlight", in: tabNamespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text(lang.t(zh, en)))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// 「出發」— paper-plane depart pill, flush inside the capsule.
    private var departButton: some View {
        Button {
            Haptics.impact(.medium)
            startAR()
        } label: {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 66, height: 44)
                .background {
                    Color.clear.glassCapsuleButton(tint: Color.navPurple)
                }
                .clipShape(Capsule())
                .shadow(color: .navPurple.opacity(0.30), radius: 6, y: 2)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Text(lang.t("出發，開始實景導航", "Depart, start AR guidance")))
    }
}

// MARK: - Shared pieces

/// Localized step indicator for the wizard screens.
struct StepProgress: View {
    @EnvironmentObject private var lang: Lang
    let step: Int
    let of: Int = 5

    private let zhNumbers = ["一", "二", "三", "四", "五"]

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<of, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index <= step ? Color.navPurple : Color(.systemFill).opacity(0.4))
                        .frame(height: 5)
                }
            }
            Text(lang.t("第\(zhNumbers[step])步，共 5 步", "Step \(step + 1) of \(of)"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(lang.t("第\(step + 1)步，共\(of)步", "Step \(step + 1) of \(of)")))
    }
}

/// Large localized headline.
struct TitleBlock: View {
    @EnvironmentObject private var lang: Lang
    let zh: String
    let en: String

    var body: some View {
        Text(lang.t(zh, en))
            .font(.system(size: 35, weight: .bold, design: .serif))
            .tracking(-0.4)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .minimumScaleFactor(0.72)
            .accessibilityAddTraits(.isHeader)
    }
}
