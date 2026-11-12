import Foundation

/// What the app publishes for the widget (v8), in the App Group, via UserDefaults.
/// Only numbers and short Overview texts; no file paths.
/// Compiled into both targets (Legroom and LegroomWidget).
///
/// The widget computes disk, memory, and processor on its own (inside the sandbox);
/// from here it uses what only the app knows: the total freed, the last cleanup, and
/// the goals' status. The metrics come along too, as a fallback.
struct WidgetSnapshot: Codable, Equatable {
    static let appGroup = "2V59R8969W.com.rafabitt.legroom"
    static let key = "widgetSnapshot.v1"

    struct GoalLine: Codable, Equatable, Hashable {
        let title: String
        let symbol: String
        let status: String
    }

    var written: Date
    // fallback (the widget prefers its own reading)
    var volumeName: String?
    var totalCapacity: Int64?
    var availableCapacity: Int64?
    var memoryUsed: UInt64?
    var memoryTotal: UInt64?
    var cpuBusy: Double?
    var cpuHistory: [Double]
    // only the app knows
    var trashedBytesTotal: Int64
    var trashedItemsTotal: Int
    var lastTrashDate: Date?
    var goals: [GoalLine]

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func read() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    @discardableResult
    func write() -> Bool {
        guard let d = Self.defaults, let data = try? JSONEncoder().encode(self) else { return false }
        d.set(data, forKey: Self.key)
        return true
    }

    /// Equal, ignoring the date and the metrics that change with every reading.
    func sameContent(as o: WidgetSnapshot) -> Bool {
        volumeName == o.volumeName && availableCapacity.map { $0 / 100_000_000 } == o.availableCapacity.map { $0 / 100_000_000 }
            && trashedBytesTotal == o.trashedBytesTotal && trashedItemsTotal == o.trashedItemsTotal
            && lastTrashDate == o.lastTrashDate && goals == o.goals
    }
}
