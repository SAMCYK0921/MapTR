//
//  Glass.swift
//  MTR Lift Guide
//
//  Apple HIG aligned design layer. Uses SwiftUI's Liquid Glass where available
//  (iOS 26+), and falls back to the native materials on earlier releases so the
//  same code base keeps one look across versions.
//

import SwiftUI

// MARK: - Brand palette

extension Color {
    static let mtrRed = Color(red: 0.62, green: 0.08, blue: 0.21)
    static let appBackground = Color(.systemGroupedBackground)

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// A color that automatically switches between light and dark variants
    /// based on the system appearance, so static design tokens stay adaptive.
    static func dynamic(light: String, dark: String) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

extension UIColor {
    /// Parses a 6-digit hex string into a UIColor (supports the `#` prefix).
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = CGFloat((int >> 16) & 0xFF) / 255
        let g = CGFloat((int >> 8) & 0xFF) / 255
        let b = CGFloat(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Liquid Glass wrapper

extension View {

    /// Floating glass surface used for cards, toolbars and pill controls.
    @ViewBuilder
    func glassSurface(cornerRadius: CGFloat = 20, tint: Color = .clear) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(Glass.clear.tint(tint.opacity(0.25)), in: .rect(cornerRadius: cornerRadius))
        } else {
            materialSurface(cornerRadius: cornerRadius)
        }
        #else
        materialSurface(cornerRadius: cornerRadius)
        #endif
    }

    /// Liquid Glass capsule — the shape used by every pill: tab bar, search fields,
    /// chips, toggles and primary pills.
    @ViewBuilder
    func glassCapsule(tint: Color = .clear) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if tint == .clear {
                self.glassEffect(Glass.clear, in: .capsule)
            } else {
                self.glassEffect(Glass.clear.tint(tint), in: .capsule)
            }
        } else {
            materialCapsule()
        }
        #else
        materialCapsule()
        #endif
    }

    /// Interactive variant for tappable pills.
    @ViewBuilder
    func glassCapsuleButton(tint: Color = .clear) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if tint == .clear {
                self.glassEffect(Glass.clear.interactive(), in: .capsule)
            } else {
                self.glassEffect(Glass.clear.interactive().tint(tint), in: .capsule)
            }
        } else {
            materialCapsule()
        }
        #else
        materialCapsule()
        #endif
    }

    private func materialCapsule() -> some View {
        self
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
            }
    }

    /// Interactive glass (buttons) — reacts to press with the system highlight.
    @ViewBuilder
    func glassButton(cornerRadius: CGFloat = 18, prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            if prominent {
                self.glassEffect(Glass.clear.interactive().tint(Color.navPurple.opacity(0.85)),
                                 in: .rect(cornerRadius: cornerRadius))
            } else {
                self.glassEffect(Glass.clear.interactive(),
                                 in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            materialFill(cornerRadius: cornerRadius, prominent: prominent)
        }
        #else
        materialFill(cornerRadius: cornerRadius, prominent: prominent)
        #endif
    }

    private func materialSurface(cornerRadius: CGFloat) -> some View {
        self
            .background(.thinMaterial, in: .rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.35), lineWidth: 0.5)
            }
    }

    private func materialFill(cornerRadius: CGFloat, prominent: Bool) -> some View {
        self.background(
            prominent ? AnyShapeStyle(Color.navPurple) : AnyShapeStyle(.regularMaterial),
            in: .rect(cornerRadius: cornerRadius)
        )
    }
}

// MARK: - Reusable components

struct LineBadge: View {
    let line: Line
    var showsLabel = true

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color(hex: line.color))
                .frame(width: 4, height: showsLabel ? 14 : 20)
            if showsLabel {
                Text("\(line.en) \(line.zh)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(line.en) \(line.zh)"))
    }
}

struct HeadsUpCard: View {
    let en: String
    let zh: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Heads-up · 注意")
                    .font(.subheadline.weight(.semibold))
                Text(zh)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if Locale.preferredLanguages.first?.hasPrefix("en") == true {
                    Text(en)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(.yellow.opacity(0.12), in: .rect(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.yellow.opacity(0.45), lineWidth: 1)
        }
    }
}

/// Floating bottom action bar — keeps the primary action inside the thumb reach zone.
struct ActionBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background {
            Color.clear.glassSurface(cornerRadius: 26)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 5)
        .padding(.horizontal, 16)
        .padding(.bottom, 76)   // clears the floating tab bar
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var isDisabled: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(isDisabled ? Color(.tertiaryLabel) : .white)
            .background(isDisabled ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.navPurple),
                        in: .rect(cornerRadius: 18, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
