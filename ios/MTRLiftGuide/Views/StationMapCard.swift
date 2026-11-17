//
//  StationMapCard.swift
//  MTR Lift Guide
//
//  Official MTR station layout page only, sized to that page's own aspect
//  ratio. Falls back to the schematic route preview if the PDF is unavailable.
//

import SwiftUI
import PDFKit

struct StationMapCard: View {
    @EnvironmentObject private var lang: Lang
    @StateObject private var service = StationMapService()
    let station: Station
    let onLocate: () -> Void

    private enum MapState {
        case loading
        case official(StationMap)
        case fallback
    }

    @State private var state: MapState = .loading
    @State private var containerWidth: CGFloat = 340

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "map.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.navPurple)
                Text(lang.t("MTR 官方站內地圖", "Official MTR station map"))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Link(destination: URL(string: "https://www.mtr.com.hk/digitalleaflet/ch/")!) {
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.navPurple)
                        .frame(width: 30, height: 30)
                        .background(Color.navPurpleSoft, in: Circle())
                }
                .accessibilityLabel(Text(lang.t("在 Safari 打開官方車站指南", "Open official station guide in Safari")))
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            content
                .frame(height: bodyHeight)
                .frame(maxWidth: .infinity)
        }
        .glassSurface(cornerRadius: 24)
        .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
        .readWidth { containerWidth = max($0 - 24, 120) }
        .task(id: station.id) { await load() }
    }

    /// Height follows the page's own aspect ratio (clamped for extreme shapes).
    private var bodyHeight: CGFloat {
        switch state {
        case .official(let map):
            return min(max(containerWidth * map.aspect, 180), 620)
        case .loading:
            return 240
        case .fallback:
            return 220
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text(lang.t("正在載入官方站內地圖…", "Loading official station map…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .official(let map):
            PDFKitView(document: map.document)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .accessibilityLabel(Text(lang.t("\(station.zh)官方站內地圖", "Official in-station map of \(station.en)")))
        case .fallback:
            VStack(spacing: 8) {
                RouteMapView(exitId: station.exits.first?.id ?? "A",
                             labels: [],
                             onLocate: onLocate)
                    .frame(height: 180)
                    .padding(.horizontal, 12)
                Text(lang.t("網絡未能載入官方地圖，先以示意路線代替。",
                            "Official map unavailable offline — showing a schematic instead."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 10)
            }
        }
    }

    private func load() async {
        state = .loading
        guard let map = await service.layout(for: station) else {
            state = .fallback
            return
        }
        state = .official(map)
    }
}

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = document
        view.scaleFactor = view.scaleFactorForSizeToFit
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
        uiView.autoScales = true
        uiView.scaleFactor = uiView.scaleFactorForSizeToFit
    }
}

/// Reads the available width of a view so the map can size itself.
private struct WidthReader: ViewModifier {
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear
                        .preference(key: WidthPreferenceKey.self, value: geo.size.width)
                }
            }
            .onPreferenceChange(WidthPreferenceKey.self) { onChange($0) }
    }
}

private struct WidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    func readWidth(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        modifier(WidthReader(onChange: onChange))
    }
}
