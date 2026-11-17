//
//  ExitListView.swift
//  MTR Lift Guide
//
//  Step 2 — pick the target exit, with the station heads-up surfaced first.
//

import SwiftUI

struct ExitListView: View {
    @EnvironmentObject private var lang: Lang
    let station: Station
    @Binding var path: [Destination]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    TitleBlock(zh: "你想要哪個出口？", en: "Which exit are you heading to?")
                    StepProgress(step: 1)
                }
                .padding(.vertical, 4)
            }

            if let note = station.note {
                Section {
                    HeadsUpCard(en: note.en, zh: note.zh)
                }
            }

            Section {
                ForEach(station.exits) { exit in
                    Button {
                        path.append(.accessibility(station, exit))
                    } label: {
                        ExitRow(exit: exit)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text(lang.t("出口", "Exits"))
            } footer: {
                if !station.verified {
                    Text(lang.t("此站出口資料按網絡結構產生，請以站內指示為準。",
                                "Exit detail for this station is generated from the network scheme. Follow on-site signage."))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("\(lang.t(station.zh, station.en)) · \(station.id)"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ExitRow: View {
    @EnvironmentObject private var lang: Lang
    let exit: StationExit

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.navPurple.opacity(0.12))
                    .frame(width: 40, height: 40)
                Text(exit.id)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.navPurple)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(lang.t(exit.nameZh, exit.nameEn))
                    .font(.body.weight(.medium))
                Text(lang.t(exit.nameEn, exit.nameZh))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Exit \(exit.id). \(lang.t(exit.nameZh, exit.nameEn))"))
    }
}
