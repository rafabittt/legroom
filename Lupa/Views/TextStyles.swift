import SwiftUI
import WidgetKit

/// Gray text that passes contrast, shared by the app and the widget (this file is in both
/// targets). Numbers from Grafite, the design directory of the Marcaí apps.
///
/// The system's `.secondary` and `.tertiary` are black at 50% and 26% in light mode: 3.95:1
/// and 1.9:1 on a white card (measured 2026-11-17), under Grafite's 4.5:1 rule. Dark mode's
/// `.tertiary` (white 25%) fails too, at 2.3:1.
enum TextGray {
    /// Secondary text (Grafite "texto secundário"): 6.4:1 on the card in both modes.
    static func secondary(_ dark: Bool) -> Color { Color(hex: dark ? 0xA1A1A8 : 0x5E5E63) }
    /// Tertiary text: the lightest gray that still reads at 4.5:1 on the card AND on the
    /// window background (5.2:1 / 4.6:1 light, 5.1:1 / 5.6:1 dark).
    static func tertiary(_ dark: Bool) -> Color { Color(hex: dark ? 0x8E8E93 : 0x6C6C70) }
}

/// Secondary text: `.foregroundStyle(.muted)` instead of `.secondary`.
///
/// Applied at each call site because on macOS a root-level `foregroundStyle(_:_:_:)`
/// reaches shapes and symbols but not `Text`. With "Increase contrast" on, each gray steps
/// up a level, as the system colors would. A widget drawn tinted or monochrome by the
/// system keeps the system grays, which is what those modes are built around.
struct MutedTextStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        guard environment.widgetRenderingMode == .fullColor else { return Color.secondary }
        let dark = environment.colorScheme == .dark
        if environment.colorSchemeContrast == .increased { return Color(hex: dark ? 0xD1D1D6 : 0x3A3A3C) }
        return TextGray.secondary(dark)
    }
}

/// Tertiary text: `.foregroundStyle(.faint)` instead of `.tertiary`.
struct FaintTextStyle: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color {
        guard environment.widgetRenderingMode == .fullColor else { return Color(nsColor: .tertiaryLabelColor) }
        let dark = environment.colorScheme == .dark
        return environment.colorSchemeContrast == .increased ? TextGray.secondary(dark) : TextGray.tertiary(dark)
    }
}

extension ShapeStyle where Self == MutedTextStyle {
    static var muted: MutedTextStyle { MutedTextStyle() }
}

extension ShapeStyle where Self == FaintTextStyle {
    static var faint: FaintTextStyle { FaintTextStyle() }
}
