//
//  AccessibilityView.swift
//  MTR Lift Guide
//
//  Step 3 — choose step-free (lift) or escalator route.
//

import SwiftUI

struct AccessibilityView: View {
    @EnvironmentObject private var lang: Lang
    let station: Station
    let exit: StationExit
    @Binding var path: [Destination]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    TitleBlock(zh: "需要升降機嗎？", en: "Do you need a lift?")
                    StepProgress(step: 2)
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(RouteMode.allCases) { mode in
                    Button {
                        path.append(.route(station, exit, mode))
                    } label: {
                        ModeRow(mode: mode)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(lang.t("無障礙選項", "Accessibility"))
            } footer: {
                Text(lang.t("所有車站均設最少一條無障礙通道；升降機狀態可能變動，請向職員查詢。",
                            "All MTR stations provide at least one step-free route. Lift status changes — check the panel or ask staff."))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("\(lang.t(station.zh, station.en)) → \(exit.id)"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ModeRow: View {
    @EnvironmentObject private var lang: Lang
    let mode: RouteMode

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(mode == .lift ? Color.green.opacity(0.15) : Color.navPurple.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: mode.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(mode == .lift ? .green : Color.navPurple)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.t(mode.titleZh, mode.titleEn))
                    .font(.body.weight(.medium))
                Text(lang.t(mode.descZh, mode.descEn))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
