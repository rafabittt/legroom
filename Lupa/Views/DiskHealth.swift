import SwiftUI
import AppKit

/// Disk "health" palette: green with plenty of free space, amber when it
/// starts getting tight, red when it's full. Everything that belongs to "the volume"
/// (Used card, orb, ring, main background blob, sidebar bar)
/// derives from here, so the whole app changes mood as the disk fills up.
struct DiskHealth: Equatable {
    /// Severity, 0 = roomy, 1 = full. It's not just the used fraction: it also
    /// weighs how many GB are left, because 170 GB free on a 500 GB disk
    /// "looks like" 65 %, but that's already little for someone who edits video or compiles.
    let fraction: Double

    init(fraction: Double) { self.fraction = min(1, max(0, fraction)) }

    /// The worse of the used fraction and the free-bytes curve.
    init(used: Int64, total: Int64) {
        let f = total > 0 ? Double(used) / Double(total) : 0
        let free = max(0, total - used)
        self.init(fraction: max(f, Self.severity(freeBytes: free)))
    }
    init(volume v: Volume) { self.init(used: v.usedCapacity, total: v.totalCapacity) }

    static let unknown = DiskHealth(fraction: 0.35)

    /// Free GB → severity curve (piecewise linear). Above 400 GB
    /// it weighs nothing; 200 GB is already "getting full"; 100 GB is "low on
    /// space"; 50 GB is critical; 20 GB is the end of the scale.
    static func severity(freeBytes: Int64) -> Double {
        let gb = Double(freeBytes) / 1_000_000_000
        let curve: [(gb: Double, s: Double)] = [(400, 0.0), (300, 0.55), (200, 0.78), (100, 0.87), (50, 0.91), (20, 1.0)]
        if gb >= curve[0].gb { return 0 }
        if gb <= curve[curve.count - 1].gb { return 1 }
        for i in 1..<curve.count where gb >= curve[i].gb {
            let hi = curve[i - 1], lo = curve[i]
            let t = (hi.gb - gb) / (hi.gb - lo.gb)
            return hi.s + (lo.s - hi.s) * t
        }
        return 1
    }

    enum Level: Int, Comparable {
        case healthy, fine, caution, warning, critical
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    /// Ranges designed for real disks: up to 60 % is fine; macOS
    /// needs 10–15 % free for snapshots, swap and updates, so
    /// above 90 % is truly critical (and only the filesystem decides that).
    var level: Level {
        switch fraction {
        case ..<0.60: return .healthy
        case ..<0.75: return .fine
        case ..<0.85: return .caution
        case ..<0.90: return .warning
        default: return .critical
        }
    }

    var label: String {
        switch level {
        case .healthy: return String(localized: "Plenty of room")
        case .fine: return String(localized: "Disk is healthy")
        case .caution: return String(localized: "Getting full")
        case .warning: return String(localized: "Low on space")
        case .critical: return String(localized: "Disk almost full")
        }
    }

    var symbol: String {
        switch level {
        case .healthy, .fine: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .warning, .critical: return "exclamationmark.triangle.fill"
        }
    }

    // MARK: Color stops (two-color gradient per stop)

    private struct Stop { let at: Double; let a: UInt32; let b: UInt32 }

    /// Light version (light background): vivid tones, but pastel enough for white text.
    private static let light: [Stop] = [
        Stop(at: 0.00, a: 0x2DD4BF, b: 0x22C55E),   // teal → green
        Stop(at: 0.60, a: 0x4ADE80, b: 0x84CC16),   // green → lime
        Stop(at: 0.75, a: 0xFACC15, b: 0xF59E0B),   // yellow → amber
        Stop(at: 0.85, a: 0xFB923C, b: 0xF97316),   // orange
        Stop(at: 0.90, a: 0xF87171, b: 0xEF4444),   // coral → red (≤10 % free: the threshold macOS needs)
        Stop(at: 1.00, a: 0xEF4444, b: 0xBE123C),   // red → crimson
    ]
    /// Dark version: more saturated, so it doesn't look washed out on a dark background.
    private static let dark: [Stop] = [
        Stop(at: 0.00, a: 0x14B8A6, b: 0x16A34A),
        Stop(at: 0.60, a: 0x22C55E, b: 0x65A30D),
        Stop(at: 0.75, a: 0xEAB308, b: 0xD97706),
        Stop(at: 0.85, a: 0xF97316, b: 0xEA580C),
        Stop(at: 0.90, a: 0xEF4444, b: 0xDC2626),
        Stop(at: 1.00, a: 0xDC2626, b: 0x9F1239),
    ]

    private static func colors(_ stops: [Stop], at f: Double) -> (Color, Color) {
        guard let upperIndex = stops.firstIndex(where: { $0.at >= f }) else {
            let s = stops[stops.count - 1]; return (Color(hex: s.a), Color(hex: s.b))
        }
        if upperIndex == 0 { let s = stops[0]; return (Color(hex: s.a), Color(hex: s.b)) }
        let lo = stops[upperIndex - 1], hi = stops[upperIndex]
        let t = (f - lo.at) / max(0.0001, hi.at - lo.at)
        return (HSB.mix(lo.a, hi.a, t).color, HSB.mix(lo.b, hi.b, t).color)
    }

    func gradientColors(dark: Bool) -> (Color, Color) {
        Self.colors(dark ? Self.dark : Self.light, at: fraction)
    }

    /// Default diagonal gradient for the cards.
    func gradient(dark: Bool) -> LinearGradient {
        let (a, b) = gradientColors(dark: dark)
        return LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Single representative color (icons, thin bars, ring).
    func accent(dark: Bool) -> Color { gradientColors(dark: dark).1 }
    func tint(dark: Bool) -> Color { gradientColors(dark: dark).0 }

    /// Sidebar panel: the health color darkened and
    /// desaturated, from lightest at the top to deepest at the bottom.
    /// Dark, neutral base; the color comes in as a glow at the top (`panelGlow`),
    /// so it doesn't turn brown when health is amber.
    func panelGradient(dark: Bool) -> LinearGradient {
        let top = Color(hex: dark ? 0x232327 : 0x2E2E34)
        let bottom = Color(hex: dark ? 0x17171A : 0x1F1F24)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
    func panelGlow(dark: Bool) -> Color {
        let base = HSB.of(accent(dark: dark))
        return HSB(h: base.h, s: min(1, base.s * 0.9), b: dark ? 0.75 : 0.85).color
    }

    /// Three-color gradient for the orb (it has more body than the cards' one).
    func heroGradient(dark: Bool) -> LinearGradient {
        let (a, b) = gradientColors(dark: dark)
        let c = HSB.rotate(b, degrees: -28, saturationBoost: 0.05).color
        return LinearGradient(colors: [a, b, c], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// HSB interpolation along the shortest hue path, so green turns
/// yellow and then red without passing through gray.
struct HSB {
    var h: Double, s: Double, b: Double

    init(h: Double, s: Double, b: Double) { self.h = h; self.s = s; self.b = b }

    init(_ hex: UInt32) {
        let c = NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255,
                        green: Double((hex >> 8) & 0xFF) / 255,
                        blue: Double(hex & 0xFF) / 255, alpha: 1)
        var hh: CGFloat = 0, ss: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        c.getHue(&hh, saturation: &ss, brightness: &bb, alpha: &aa)
        h = hh; s = ss; b = bb
    }

    var color: Color { Color(hue: h, saturation: s, brightness: b) }

    static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> HSB {
        let x = HSB(a), y = HSB(b)
        var dh = y.h - x.h
        if dh > 0.5 { dh -= 1 } else if dh < -0.5 { dh += 1 }
        var h = x.h + dh * t
        if h < 0 { h += 1 } else if h > 1 { h -= 1 }
        return HSB(h: h, s: x.s + (y.s - x.s) * t, b: x.b + (y.b - x.b) * t)
    }

    static func of(_ c: Color) -> HSB {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? NSColor(c)
        var hh: CGFloat = 0, ss: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        ns.getHue(&hh, saturation: &ss, brightness: &bb, alpha: &aa)
        return HSB(h: Double(hh), s: Double(ss), b: Double(bb))
    }

    static func rotate(_ c: Color, degrees: Double, saturationBoost: Double = 0) -> HSB {
        let ns = NSColor(c).usingColorSpace(.sRGB) ?? NSColor(c)
        var hh: CGFloat = 0, ss: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        ns.getHue(&hh, saturation: &ss, brightness: &bb, alpha: &aa)
        var h = Double(hh) + degrees / 360
        if h < 0 { h += 1 } else if h > 1 { h -= 1 }
        return HSB(h: h, s: min(1, Double(ss) + saturationBoost), b: Double(bb))
    }
}
