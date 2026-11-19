//
//  RecentsView.swift
//  MTR Lift Guide
//
//  最近 tab — journeys you have navigated, one tap to re-run.
//

import SwiftUI

struct RecentsView: View {
    @EnvironmentObject private var lang: Lang
    @EnvironmentObject private var network: Network
    @EnvironmentObject private var journey: JourneyStore
    @EnvironmentObject private var wallet: CoinWallet
    @Binding var path: [Destination]
    let onStartAR: () -> Void

    private let coinGold = Color(red: 1.0, green: 0.79, blue: 0.35)

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    TitleBlock(zh: "最近路線", en: "Recent journeys")
                    Text(lang.t("點一下即可重新導航。", "Tap any journey to navigate it again."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                walletCard
                    .padding(.vertical, 4)
            }

            if journey.recents.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(lang.t("還沒有路線記錄", "No journeys yet"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else {
                ForEach(journey.recents) { recent in
                    row(for: recent)
                }
                .onDelete { offsets in
                    journey.recents.remove(atOffsets: offsets)
                }
            }
        }
        .listStyle(.insetGrouped)
        // Clears the floating tab bar now that it is an overlay.
        .safeAreaPadding(.bottom, 104)
        .navigationTitle(Text(lang.t("最近", "Recent")))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Running coin balance plus how many people the user has helped.
    private var walletCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(coinGold.opacity(0.16))
                    .frame(width: 46, height: 46)
                Image(systemName: "circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(coinGold)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(lang.t("我的金幣", "My coins"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(wallet.total.formatted())
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Label(lang.t("已協助 \(wallet.peopleHelped) 人", "Helped \(wallet.peopleHelped)"),
                      systemImage: "hand.raised.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.navPurple)
                Text(lang.t("每次協助 +\(CoinWallet.helpReward)",
                            "+\(CoinWallet.helpReward) per person"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .animation(.snappy(duration: 0.3), value: wallet.total)
    }

    @ViewBuilder
    private func row(for recent: RecentJourney) -> some View {
        if let station = network.stations.first(where: { $0.id == recent.stationId }),
           let exit = station.exits.first(where: { $0.id == recent.exitId }) {
            Button {
                path.append(.route(station, exit, recent.mode))
            } label: {
                HStack(spacing: 12) {
                    Text(exit.id)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.navPurple, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(lang.t(station.zh, station.en)) → \(lang.t("出口", "Exit")) \(exit.id)")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            Text(lang.t(recent.mode.titleZh, recent.mode.titleEn))
                            Text(recent.date, style: .relative)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
