import Foundation

enum Format {
    static let bytes: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func bytes(_ n: Int64) -> String { bytes.string(fromByteCount: n) }

    /// Memory in the units used by About This Mac and Activity Monitor (base 1024):
    /// 38,654,705,664 bytes show as "36 GB", not "38.65 GB".
    static let memoryFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .memory
        f.allowsNonnumericFormatting = false
        return f
    }()

    static func memory(_ n: Int64) -> String { memoryFormatter.string(fromByteCount: n) }

    static func count(_ n: Int) -> String {
        n.formatted(.number.locale(.current))
    }

    static func seconds(_ d: TimeInterval) -> String {
        d < 60 ? String(localized: "\(d.formatted(.number.precision(.fractionLength(1)))) s") : String(localized: "\((d / 60).safeInt) min")
    }

    static func date(_ d: Date?) -> String {
        guard let d else { return "—" }
        return d.formatted(date: .abbreviated, time: .shortened)
    }

    /// "just now", "2 hours ago", "3 days ago".
    static func since(_ d: Date, now: Date = Date()) -> String {
        now.timeIntervalSince(d) < 60 ? String(localized: "just now") : relative(d)
    }

    static func relative(_ d: Date?) -> String {
        guard let d else { return String(localized: "never") }
        let f = RelativeDateTimeFormatter()
        f.locale = .current
        f.unitsStyle = .full
        return f.localizedString(for: d, relativeTo: Date())
    }
}

extension Double {
    /// Integer conversion that never crashes the app: `Int(x)` traps on NaN,
    /// infinity, or out-of-range values, and system readings can produce all three.
    var safeInt: Int {
        guard isFinite else { return 0 }
        if self >= 9.0e18 { return Int.max }
        if self <= -9.0e18 { return Int.min }
        return Int(self)
    }
}
