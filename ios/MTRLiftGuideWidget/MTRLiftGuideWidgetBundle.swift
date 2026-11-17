//
//  MTRLiftGuideWidgetBundle.swift
//  MTR Lift Guide Widget
//
//  Dynamic Island (Live Activity) presentation for AR guidance:
//  compact "small island" shows exit + compass direction + travel mode + progress,
//  expanded "big island" lists the whole step-by-step journey.
//
//  Accent color is the MTR brand red — it stays legible against the black island.
//

import ActivityKit
import WidgetKit
import SwiftUI

@main
struct MTRLiftGuideWidgetBundle: WidgetBundle {
    var body: some Widget {
        MTRGuidanceLiveActivity()
    }
}

struct MTRGuidanceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GuidanceActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // ── Expanded (big island) ───────────────────────────────
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.stationName)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                        HStack(spacing: 3) {
                            Image(systemName: context.state.modeSymbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.mtrRed)
                            Text(context.state.modeTitle)
                                .font(.caption2)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("出口 \(context.attributes.exitID)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.mtrRed)
                        Text("\(context.state.stepIndex + 1)/\(context.state.totalSteps)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 6) {
                        Image(systemName: context.state.directionSymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.mtrRed)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.state.stepTitle)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(context.state.directionText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(context.state.steps.enumerated()), id: \.offset) { offset, step in
                            let isCurrent = offset == context.state.stepIndex
                            HStack(spacing: 6) {
                                Image(systemName: step.symbol)
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(width: 16)
                                    .foregroundStyle(isCurrent ? Color.mtrRed : Color.secondary)
                                Text(step.title)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                                Spacer(minLength: 0)
                                if isCurrent {
                                    Circle()
                                        .fill(Color.mtrRed)
                                        .frame(width: 6, height: 6)
                                }
                            }
                        }
                    }
                }
            } compactLeading: {
                // ── Compact leading: compass direction + exit ──────────
                HStack(spacing: 3) {
                    Image(systemName: context.state.directionSymbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.mtrRed)
                    Text(context.attributes.exitID)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.mtrRed)
                }
            } compactTrailing: {
                // ── Compact trailing: travel mode + progress ────────────
                HStack(spacing: 3) {
                    Image(systemName: context.state.modeSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.mtrRed)
                    Text("\(context.state.stepIndex + 1)/\(context.state.totalSteps)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            } minimal: {
                Image(systemName: context.state.directionSymbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.mtrRed)
            }
        }
    }
}

/// Lock-screen / banner presentation.
private struct LockScreenView: View {
    let context: ActivityViewContext<GuidanceActivityAttributes>

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: context.state.directionSymbol)
                .font(.title3)
                .foregroundStyle(Color.mtrRed)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(context.attributes.stationName) → 出口 \(context.attributes.exitID)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(context.state.stepTitle)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: context.state.modeSymbol)
                        .font(.caption2)
                        .foregroundStyle(Color.mtrRed)
                    Text(context.state.modeTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(context.state.stepIndex + 1)/\(context.state.totalSteps)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Color.mtrRed)
        }
        .padding(.horizontal, 12)
    }
}

private extension Color {
    /// MTR brand red — bright enough to stay visible on the black Dynamic Island.
    static let mtrRed = Color(hex: "E31E24")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        self.init(red: Double((int >> 16) & 0xFF) / 255,
                  green: Double((int >> 8) & 0xFF) / 255,
                  blue: Double(int & 0xFF) / 255)
    }
}
