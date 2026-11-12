import SwiftUI
import Darwin

// The widget's own readings, inside the sandbox. Nothing here walks folders:
// the disk is just the root volume's capacity (one call); memory and CPU
// are kernel counters.

extension Color {
    /// The app defines this in Theme.swift, which isn't part of the widget.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum WidgetPalette {
    static func background(_ dark: Bool) -> Color { dark ? Color(hex: 0x1E1E21) : .white }
    static func track(_ dark: Bool) -> Color { Color.primary.opacity(dark ? 0.12 : 0.08) }
}

enum DiskReader {
    /// Startup volume, with the same keys as the app (`Volume.mounted()`).
    static func root() -> Volume? {
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeNameKey, .volumeTotalCapacityKey,
                                         .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? url.resourceValues(forKeys: keys), let total = v.volumeTotalCapacity, total > 0 else { return nil }
        let available = Int64(v.volumeAvailableCapacity ?? 0)
        return Volume(url: url,
                      name: v.volumeLocalizedName ?? v.volumeName ?? "Macintosh HD",
                      totalCapacity: Int64(total),
                      availableCapacity: available,
                      availableForImportantUsage: v.volumeAvailableCapacityForImportantUsage ?? available,
                      isInternal: true, isRemovable: false, isEjectable: false, isReadOnly: false, isRootVolume: true)
    }
}

/// CPU: the difference between two host_cpu_load_info readings. Between one
/// timeline update and the next (~15 min), the widget stores the ticks in its
/// own container and shows the average over the interval; the short history
/// becomes the sparkline. With no previous reading, it samples for 1 s.
enum CPUReader {
    private static let ticksKey = "cpu.ticks"
    private static let dateKey = "cpu.date"
    private static let historyKey = "cpu.history"
    static let historyLength = 16

    private static func ticks() -> [Double]? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return nil }
        let t = withUnsafeBytes(of: info.cpu_ticks) { raw in (0..<Int(CPU_STATE_MAX)).map { Double(raw.load(fromByteOffset: $0 * 4, as: UInt32.self)) } }
        return t
    }

    private static func busy(from a: [Double], to b: [Double]) -> Double? {
        guard a.count == b.count, a.count >= Int(CPU_STATE_MAX) else { return nil }
        func d(_ i: Int32) -> Double { max(0, b[Int(i)] - a[Int(i)]) }
        let user = d(CPU_STATE_USER) + d(CPU_STATE_NICE), sys = d(CPU_STATE_SYSTEM), idle = d(CPU_STATE_IDLE)
        let total = user + sys + idle
        return total > 0 ? (user + sys) / total : nil
    }

    static var history: [Double] { UserDefaults.standard.array(forKey: historyKey) as? [Double] ?? [] }

    /// `record` saves the point to the history (only the timeline records; the gallery doesn't).
    static func sample(record: Bool) -> Double? {
        let d = UserDefaults.standard
        guard let now = ticks() else { return nil }
        var value: Double?
        if let prev = d.array(forKey: ticksKey) as? [Double], let at = d.object(forKey: dateKey) as? Date {
            let age = Date().timeIntervalSince(at)
            // Another widget size just read it: reuse the same value.
            if age < 30, let last = history.last { return last }
            if age <= 3 * 3600 { value = busy(from: prev, to: now) }
        }
        if value == nil {
            // No previous reading: sample for 1 s (the kernel counters move slowly).
            usleep(1_000_000)
            if let again = ticks() { value = busy(from: now, to: again) }
        }
        if record {
            d.set(now, forKey: ticksKey)
            d.set(Date(), forKey: dateKey)
            if let value { d.set(Array((history + [value]).suffix(historyLength)), forKey: historyKey) }
        }
        return value
    }
}
