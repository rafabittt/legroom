import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Legroom's design tokens.
///
/// Source of truth since 2026-11-17: Grafite v1.0, the design directory shared by the
/// Marcaí apps (kept outside this repository: rules in its DESIGN.md, numbers in its
/// tokens/Grafite.swift). Every value here must match `Grafite.swift`. A design decision
/// changes there first and is then mirrored here; whatever Legroom keeps different on
/// purpose is listed in the directory's APPS.md. The file isn't imported: only the numbers match.
enum Theme {
    // Shape (Grafite.cornerXL / cornerL / cornerM / cornerS)
    static let cornerXL: CGFloat = 20   // main card, sidebar, overlay window
    static let cornerL: CGFloat = 16    // regular card
    static let cornerM: CGFloat = 10    // what sits inside a card
    static let cornerS: CGFloat = 6     // tag

    // Space (Grafite.gap / cardPadding / pagePadding / sidebarWidth / sidebarInset)
    static let gap: CGFloat = 14
    static let cardPadding: CGFloat = 18
    static let pagePadding: CGFloat = 24
    static let sidebarWidth: CGFloat = 232
    static let sidebarInset: CGFloat = 12

    /// v4 direction (rondesignlab refs + Apple principles): near-neutral light-gray
    /// background, white cards with a 1 pt border and a short shadow, black/gray text,
    /// ONE vivid color per screen (disk health). In dark mode, the same with system grays.
    static let lightBackground = Color(hex: 0xF0F0F3)
    static let darkBackground = Color(hex: 0x141416)
    static let lightCard = Color.white
    static let darkCard = Color(hex: 0x1E1E21)
    static let darkCardElevated = Color(hex: 0x242428)
    static let lightHairline = Color.black.opacity(0.06)
    static let darkHairline = Color.white.opacity(0.08)
    static let destructive = Color(hex: 0xFF3B30)
    static let success = Color(hex: 0x34C759)

    static func gradient(_ a: UInt32, _ b: UInt32) -> LinearGradient {
        LinearGradient(colors: [Color(hex: a), Color(hex: b)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Treemap category colors: low-saturation midtones, so the map informs
    /// without shouting. The only place in the app with more than one color at once.
    static func categoryColor(_ c: FileCategory) -> Color {
        switch c {
        case .directory: return Color(hex: 0x8E95B5)
        case .application: return Color(hex: 0x7F8CD9)
        case .bundle: return Color(hex: 0xA3A9CB)
        case .image: return Color(hex: 0x6FBF8E)
        case .video: return Color(hex: 0xD97A84)
        case .audio: return Color(hex: 0xD9B36A)
        case .archive: return Color(hex: 0xD9966A)
        case .document: return Color(hex: 0x74A4DD)
        case .code: return Color(hex: 0x9A9AA3)
        case .diskImage: return Color(hex: 0xC98DB8)
        case .other: return Color(hex: 0xB8B8BF)
        }
    }

    /// Kept for compatibility: today it is just the flat category color.
    static func categoryGradient(_ c: FileCategory) -> LinearGradient {
        let col = categoryColor(c)
        return LinearGradient(colors: [col, col], startPoint: .top, endPoint: .bottom)
    }

    static func background(_ dark: Bool) -> Color { dark ? darkBackground : lightBackground }
    static func card(_ dark: Bool) -> Color { dark ? darkCard : lightCard }
    static func hairline(_ dark: Bool) -> Color { dark ? darkHairline : lightHairline }
    /// Quiet fill (Grafite.fill): icon tile, track, hover.
    static func fill(_ dark: Bool) -> Color { dark ? .white.opacity(0.07) : .black.opacity(0.05) }

    /// Ink (Grafite.ink / inkText): the main button, the active tab, the hold button.
    /// Never pure black or pure white.
    static func ink(_ dark: Bool) -> Color { Color(hex: dark ? 0xF5F5F7 : 0x1D1D1F) }
    /// The Legroom green: one tone for the mark, the app icon and the website.
    /// It's the healthy end of the disk-health palette (`#2DD4BF` → `#22C55E`), at its midpoint.
    static let brandGreen = Color(hex: 0x28CD8F)
    static func inkText(_ dark: Bool) -> Color { dark ? Color(hex: 0x1D1D1F) : .white }

    /// Gray text: the numbers live in TextStyles.swift (`TextGray`), which the widget shares.
    /// Use `.foregroundStyle(.muted)` and `.foregroundStyle(.faint)`; these two functions are
    /// for places that need a plain `Color`. The sidebar keeps the system grays: it's always
    /// dark, where `.secondary` reads at 5.2:1.
    static func textSecondary(_ dark: Bool) -> Color { TextGray.secondary(dark) }
    static func textTertiary(_ dark: Bool) -> Color { TextGray.tertiary(dark) }

    // The sidebar panel colors (Grafite.sidebarTop / sidebarBottom: #2E2E34 → #1F1F24 by day,
    // #232327 → #17171A at night) live in `DiskHealth.panelGradient`, because that file is
    // shared with the widget target and this one isn't.

    // Motion (Grafite.hoverIn / hoverOut / select): springs without bounce, fast in, slow out.
    static let hoverIn = Animation.spring(response: 0.28, dampingFraction: 1.0)
    static let hoverOut = Animation.spring(response: 0.6, dampingFraction: 1.0)
    static let select = Animation.spring(response: 0.3, dampingFraction: 1.0)
    static let pressScale: CGFloat = 0.96
    static let cardHoverScale: CGFloat = 1.004
}

/// Window background: a single color. The only "light" is a nearly invisible white
/// glow at the top, so the background doesn't look like a flat slab.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme
    var health: DiskHealth = .unknown
    var goal: Goal = .map
    var body: some View {
        let dark = scheme == .dark
        ZStack {
            Theme.background(dark)
            if !dark {
                RadialGradient(colors: [.white.opacity(0.7), .clear], center: .top, startRadius: 0, endRadius: 700)
            }
        }
        .ignoresSafeArea()
    }
}

/// Card: white with a 1 pt border and a short shadow in light mode; system gray in dark mode.
struct ContentCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var corner: CGFloat = Theme.cornerL
    /// Reacts to the cursor: grows 0.4%, the shadow deepens and the border lights up. Fast in, slow out.
    var hoverable = true
    @State private var hover = false
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let dark = scheme == .dark
        let lit = hover && hoverable
        content
            .background(shape.fill(Theme.card(dark)))
            .overlay(shape.strokeBorder(lit ? Color.primary.opacity(dark ? 0.18 : 0.12) : Theme.hairline(dark), lineWidth: 1))
            .shadow(color: .black.opacity(dark ? (lit ? 0.5 : 0.35) : (lit ? 0.10 : 0.05)), radius: lit ? (dark ? 24 : 18) : (dark ? 18 : 12), y: lit ? 10 : 6)
            .scaleEffect(lit && !reduceMotion ? Theme.cardHoverScale : 1)
            .onHover { h in
                withAnimation(h ? Theme.hoverIn : Theme.hoverOut) { hover = h }
            }
    }
}

/// Glass for the navigation layer: Liquid Glass on macOS 26+, thin material before that.
struct NavigationGlass: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var corner: CGFloat = Theme.cornerL
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        content
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(Theme.hairline(scheme == .dark), lineWidth: 1))
            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.10), radius: 24, y: 12)
    }
}

extension View {
    func contentCard(corner: CGFloat = Theme.cornerL, hoverable: Bool = true) -> some View { modifier(ContentCard(corner: corner, hoverable: hoverable)) }
    func navigationGlass(corner: CGFloat = Theme.cornerL) -> some View { modifier(NavigationGlass(corner: corner)) }
}

/// Volume indicator kinds. Only "Used" carries color (disk health);
/// the others are monochrome.
enum KPIKind {
    case used(DiskHealth), purgeable, free, mapped
    func accent(dark: Bool) -> Color? {
        if case .used(let h) = self { return h.accent(dark: dark) }
        return nil
    }
    var symbol: String {
        switch self {
        case .used: return "internaldrive"
        case .purgeable: return "arrow.3.trianglepath"
        case .free: return "circle.dashed"
        case .mapped: return "square.grid.3x3.topleft.filled"
        }
    }
}

/// Indicator card: small title, large black number, gray caption.
/// On "Used", a ring and a soft blob in the health color; on the others, nothing colored.
struct GradientCard: View {
    let title: String
    let value: Int64
    let kind: KPIKind
    var caption: String? = nil
    var fraction: Double? = nil
    var help: String? = nil
    @Environment(\.colorScheme) private var scheme

    private var parts: (number: String, unit: String) {
        let s = Format.bytes(value)
        if let space = s.lastIndex(of: " ") {
            return (String(s[..<space]), String(s[s.index(after: space)...]))
        }
        return (s, "")
    }

    private var dark: Bool { scheme == .dark }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerXL, style: .continuous)
        let accent = kind.accent(dark: dark)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: kind.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.muted)
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.muted).lineLimit(1)
            }
            .padding(.trailing, fraction == nil ? 0 : 52)
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                RollingNumber(text: parts.number, font: .system(size: 30, weight: .semibold), tracking: -0.8)
                Text(parts.unit).font(.system(size: 13, weight: .medium)).foregroundStyle(.muted)
            }
            .foregroundStyle(.primary)
            if let caption {
                Text(caption).font(.system(size: 11)).foregroundStyle(.muted)
                    .lineLimit(1).truncationMode(.tail).padding(.top, 2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 124)
        .background {
            shape.fill(Theme.card(dark))
                .overlay {
                    if let accent {
                        // the header's only color: a soft blob, like a tile from the refs
                        Circle().fill(accent).frame(width: 170, height: 170).blur(radius: 48)
                            .offset(x: 120, y: 50).opacity(dark ? 0.28 : 0.30)
                            .animation(.easeInOut(duration: 1.0), value: accent)
                    }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Theme.hairline(dark), lineWidth: 1))
        }
        .overlay(alignment: .topTrailing) {
            if let fraction {
                Ring(fraction: fraction, accent: accent ?? .secondary).frame(width: 44, height: 44).padding(14)
            }
        }
        .cursorReactive(corner: Theme.cornerXL, spotlight: dark ? .white : .black, intensity: dark ? 0.06 : 0.035, tilt: 2, lift: 1.01, borderGlow: 0.12)
        .help(help ?? "")
    }

    private struct Ring: View {
        let fraction: Double
        let accent: Color
        var body: some View {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.08), lineWidth: 4)
                Circle().trim(from: 0, to: max(0.01, min(1, fraction)))
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.8, dampingFraction: 1.0), value: fraction)
                RollingNumber(text: "\((fraction * 100).rounded().safeInt)%", font: .system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
    }
}

/// Pill selector (rondesignlab refs): active item is Grafite ink (#1D1D1F with white text in
/// light mode, #F5F5F7 with dark text in dark mode); the rest is just gray text.
struct PillTabs<T: Hashable>: View {
    let items: [(T, String, String?)]   // value, title, symbol
    @Binding var selection: T
    @Environment(\.colorScheme) private var scheme
    @Namespace private var ns

    var body: some View {
        let dark = scheme == .dark
        HStack(spacing: 2) {
            ForEach(items, id: \.0) { item in
                let active = item.0 == selection
                PillTabItem(active: active, dark: dark, title: item.1, symbol: item.2, ns: ns) {
                    withAnimation(Theme.select) { selection = item.0 }
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.card(dark)))
        .overlay(Capsule().strokeBorder(Theme.hairline(dark), lineWidth: 1))
    }
}

private struct PillTabItem: View {
    let active: Bool
    let dark: Bool
    let title: String
    let symbol: String?
    let ns: Namespace.ID
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .semibold)) }
                if !title.isEmpty { Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize() }
            }
            .padding(.horizontal, title.isEmpty ? 9 : 12).padding(.vertical, 6)
            .foregroundStyle(active ? Theme.inkText(dark) : (hover ? Color.primary : Theme.textSecondary(dark)))
            .background {
                if active {
                    Capsule().fill(Theme.ink(dark)).matchedGeometryEffect(id: "pill", in: ns)
                } else if hover {
                    Capsule().fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hover = h } }
    }
}

/// Primary pill button: Grafite ink (#1D1D1F in light mode, #F5F5F7 in dark mode). Responds to presses.
struct PillButton: View {
    let title: String
    var systemImage: String? = nil
    var prominent = true
    var compact = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    @State private var hover = false
    var body: some View {
        let dark = scheme == .dark
        Button(action: action) {
            HStack(spacing: compact ? 5 : 7) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: compact ? 11 : 12, weight: .semibold)) }
                Text(title).font(.system(size: compact ? 12 : 13, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, compact ? 12 : 16).padding(.vertical, compact ? 7 : 9)
            .foregroundStyle(prominent ? Theme.inkText(dark) : Color.primary)
            .background(Capsule().fill(prominent ? Theme.ink(dark) : Theme.card(dark)))
            .overlay(Capsule().fill(Color.primary.opacity(hover ? (prominent ? 0 : 0.05) : 0)))
            .overlay(Capsule().fill(prominent ? Color.white.opacity(hover && !dark ? 0.12 : 0) : .clear))
            .overlay(Capsule().strokeBorder(prominent ? .clear : (hover ? Color.primary.opacity(dark ? 0.22 : 0.16) : Theme.hairline(dark)), lineWidth: 1))
            .shadow(color: .black.opacity(hover ? (dark ? 0.4 : 0.12) : 0), radius: 10, y: 5)
            .scaleEffect(pressed ? Theme.pressScale : (hover && !reduceMotion ? 1.03 : 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(h ? .spring(response: 0.25, dampingFraction: 0.9) : .spring(response: 0.5, dampingFraction: 1.0)) { hover = h } }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !pressed { withAnimation(.easeOut(duration: 0.08)) { pressed = true } } }
            .onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { pressed = false } })
    }
}

/// Thin history line (CPU, network), with a filled area under the curve.
struct Sparkline: View {
    let values: [Double]      // 0…1, already normalized
    var color: Color = .primary
    var fill = true
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let n = max(values.count, 2)
            let pts: [CGPoint] = values.enumerated().map { i, v in
                CGPoint(x: w * CGFloat(i) / CGFloat(n - 1), y: h - h * CGFloat(min(1, max(0, v))))
            }
            ZStack {
                if fill, pts.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: pts[0].x, y: h))
                        for pt in pts { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: h))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                }
                if pts.count > 1 {
                    Path { p in p.move(to: pts[0]); for pt in pts.dropFirst() { p.addLine(to: pt) } }
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    Circle().fill(color).frame(width: 5, height: 5).position(pts[pts.count - 1])
                }
            }
            .animation(.linear(duration: 0.3), value: values.count)
        }
    }
}
