//
//  MoreView.swift
//  MTR Lift Guide
//
//  更多 tab — language, data provenance and about.
//

import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var lang: Lang
    @EnvironmentObject private var network: Network
    @AppStorage(VoiceService.voiceLanguageKey) private var voiceLanguage: String = VoiceLanguage.cantonese.rawValue

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    TitleBlock(zh: "更多設定", en: "More")
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker(selection: $lang.code) {
                    Text("中文").tag(Lang.Code.zh)
                    Text("English").tag(Lang.Code.en)
                } label: {
                    Label(lang.t("語言", "Language"), systemImage: "globe")
                }

                Picker(selection: $voiceLanguage) {
                    ForEach(VoiceLanguage.allCases) { voice in
                        Text(lang.t(voice.displayZh, voice.displayEn)).tag(voice.rawValue)
                    }
                } label: {
                    Label(lang.t("語音導航語言", "Voice guidance language"),
                          systemImage: "speaker.wave.2")
                }
            } header: {
                Text(lang.t("偏好設定", "Preferences"))
            } footer: {
                Text(lang.t("適用於路線與實景導航的語音播報。", "Applies to spoken turn-by-turn guidance."))
            }

            Section {
                LabeledContent(lang.t("資料版本", "Data version"), value: network.meta.version)
                LabeledContent(lang.t("車站數目", "Stations"),
                               value: "\(network.stations.count)")
                LabeledContent(lang.t("出口數目", "Exits"),
                               value: "\(network.stations.reduce(0) { $0 + $1.exits.count })")
            } header: {
                Text(lang.t("資料來源", "Data"))
            } footer: {
                Text(lang.t(network.meta.provenanceNote, network.meta.provenanceNote))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Section {
                Text(lang.t(network.meta.disclaimerZh, network.meta.disclaimerEn))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(lang.t("免責聲明", "Disclaimer"))
            }
        }
        .listStyle(.insetGrouped)
        // Clears the floating tab bar now that it is an overlay.
        .safeAreaPadding(.bottom, 104)
        .navigationTitle(Text(lang.t("更多", "More")))
        .navigationBarTitleDisplayMode(.inline)
    }
}
