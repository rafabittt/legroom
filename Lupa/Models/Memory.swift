import Foundation
import Darwin

/// Reads physical memory via host_statistics64, with the same math as Activity
/// Monitor: used = active + wired + compressed; "cached files" are the inactive
/// pages the system recycles when it needs to.
struct MemorySnapshot: Equatable {
    let total: UInt64
    let used: UInt64
    let wired: UInt64
    let compressed: UInt64
    let inactive: UInt64
    let free: UInt64
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
    /// Space that can still be handed to apps without compressing or paging.
    var available: UInt64 { free + inactive }

    var pressureLabel: String {
        switch usedFraction {
        case ..<0.65: return String(localized: "Memory has room")
        case ..<0.85: return String(localized: "Normal memory use")
        default: return String(localized: "Memory under pressure")
        }
    }

    /// Short form for places that already say "Memory" (the menu bar card).
    var pressureShort: String {
        switch usedFraction {
        case ..<0.65: return String(localized: "has room")
        case ..<0.85: return String(localized: "normal use")
        default: return String(localized: "under pressure")
        }
    }

    static func take() -> MemorySnapshot? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let wired = UInt64(info.wire_count) * page
        let active = UInt64(info.active_count) * page
        let compressed = UInt64(info.compressor_page_count) * page
        let inactive = UInt64(info.inactive_count) * page
        let free = UInt64(info.free_count) * page
        return MemorySnapshot(total: ProcessInfo.processInfo.physicalMemory,
                              used: active + wired + compressed,
                              wired: wired, compressed: compressed, inactive: inactive, free: free)
    }
}

/// "Free up memory": asks the system for real space (allocates and touches pages) so
/// it discards cached files and inactive pages, then gives everything back right away.
/// It's the same trick memory utilities use; the gain lasts until apps need the
/// memory again. Limits: never more than half the RAM, and it stops if free memory
/// drops below 1 GB, so open apps aren't pushed into swap.
enum MemoryCleaner {
    struct Outcome { let before: MemorySnapshot; let after: MemorySnapshot; var freed: Int64 { Int64(after.free) - Int64(before.free) } }

    static func run() async -> Outcome? {
        await Task.detached(priority: .userInitiated) { () -> Outcome? in
            guard let before = MemorySnapshot.take() else { return nil }
            let chunk = 256 << 20
            let cap = min(before.total / 2, before.available)
            var blocks: [UnsafeMutableRawPointer] = []
            var allocated: UInt64 = 0
            while allocated + UInt64(chunk) <= cap {
                if let now = MemorySnapshot.take(), now.free < (1 << 30) { break }
                guard let b = malloc(chunk) else { break }
                memset(b, 1, chunk)          // touch the pages so the kernel has to actually hand them over
                blocks.append(b)
                allocated += UInt64(chunk)
            }
            usleep(150_000)
            for b in blocks { free(b) }
            usleep(250_000)
            guard let after = MemorySnapshot.take() else { return nil }
            return Outcome(before: before, after: after)
        }.value
    }
}
