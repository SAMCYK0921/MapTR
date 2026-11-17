//
//  StationListView.swift
//  MTR Lift Guide
//
//  車站 tab (mode: .tab) and the home-screen station picker (mode: .picker).
//

import SwiftUI

struct StationListView: View {
    enum Mode { case tab, picker }

    @EnvironmentObject private var lang: Lang
    @EnvironmentObject private var network: Network
    @EnvironmentObject private var journey: JourneyStore
    let mode: Mode
    @Binding var path: [Destination]

    @State private var query = ""

    private var results: [Station] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return network.stations }
        let lowered = trimmed.lowercased()
        return network.stations.filter {
            $0.en.lowercased().contains(lowered)
                || $0.zh.contains(trimmed)
                || $0.id.lowercased().contains(lowered)
        }
    }

    private var grouped: [(Line, [Station])] {
        network.lines.compactMap { line in
            let members = results.filter { $0.lineIds.contains(line.id) }
            return members.isEmpty ? nil : (line, members)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            stationList
        }
        .navigationTitle(Text(mode == .picker
                              ? lang.t("選擇車站", "Choose station")
                              : lang.t("車站", "Stations")))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Custom top search field — the system `.searchable` bar is placed at the
    /// bottom on iOS 26 and gets hidden behind the floating tab bar.
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(lang.t("搜尋車站…", "Search station…"), text: $query)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
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
        .frame(height: 46)
        .glassCapsule()
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var stationList: some View {
        List {
            if mode == .tab {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        TitleBlock(zh: "你現在在哪個車站？", en: "Which station are you in?")
                    }
                    .padding(.vertical, 4)
                }
            }

            if results.isEmpty {
                Section {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                ForEach(grouped, id: \.0.id) { line, stations in
                    Section {
                        ForEach(stations) { station in
                            Button {
                                journey.setCurrentStation(station)
                                path.append(.exits(station))
                            } label: {
                                StationRow(station: station, line: line,
                                           isCurrent: journey.currentStationId == station.id)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("\(lang.t(line.zh, line.en))")
                    }
                }
            }

            Section {
                Text(lang.t(network.meta.disclaimerZh, network.meta.disclaimerEn))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("\(network.stations.count) " + lang.t("個車站 · 資料版本 ", "stations · data ") + network.meta.version)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.visible)
        // Clears the floating tab bar now that it is an overlay.
        .safeAreaPadding(.bottom, 104)
        .scrollDismissesKeyboard(.immediately)
    }
}

private struct StationRow: View {
    @EnvironmentObject private var lang: Lang
    let station: Station
    let line: Line
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(hex: line.color))
                .frame(width: 6, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.t(station.zh, station.en))
                    .font(.body.weight(.medium))
                Text(lang.t(station.en, station.zh))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.navPurple)
            }
            Text("\(station.exits.count) " + lang.t("個出口", "exits"))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
