import Foundation

/// A mounted volume, with its capacity and an estimate of purgeable space.
/// Uses only public NSURL keys: the difference between the capacity available
/// "for important usage" and the regular available capacity is what the system
/// can free on its own (caches, local snapshots, etc.).
struct Volume: Identifiable, Hashable {
    let url: URL
    let name: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    let availableForImportantUsage: Int64
    let isInternal: Bool
    let isRemovable: Bool
    let isEjectable: Bool
    let isReadOnly: Bool
    let isRootVolume: Bool

    var id: URL { url }
    /// Free space as System Settings and Finder show it: includes what macOS
    /// frees on its own when needed (caches, local snapshots). This is the number
    /// the app shows everywhere, so it matches the Mac's.
    var free: Int64 { max(availableForImportantUsage, availableCapacity) }
    var usedCapacity: Int64 { max(0, totalCapacity - free) }
    var purgeableEstimate: Int64 { max(0, availableForImportantUsage - availableCapacity) }
    var usedExcludingPurgeable: Int64 { max(0, usedCapacity - purgeableEstimate) }
    var usedFraction: Double { totalCapacity > 0 ? Double(usedCapacity) / Double(totalCapacity) : 0 }

    static let resourceKeys: Set<URLResourceKey> = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
        .volumeIsReadOnlyKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey,
    ]

    /// Volumes visible to the user (ignores Preboot, VM, Recovery, and the like).
    static func mounted() -> [Volume] {
        let fm = FileManager.default
        let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: Array(resourceKeys),
                                        options: [.skipHiddenVolumes]) ?? []
        var result: [Volume] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: resourceKeys) else { continue }
            if v.volumeIsBrowsable == false { continue }
            if url.path.hasPrefix("/System/Volumes/") { continue }
            let name = v.volumeLocalizedName ?? v.volumeName ?? url.lastPathComponent
            result.append(Volume(
                url: url,
                name: name,
                totalCapacity: Int64(v.volumeTotalCapacity ?? 0),
                availableCapacity: Int64(v.volumeAvailableCapacity ?? 0),
                availableForImportantUsage: v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0),
                isInternal: v.volumeIsInternal ?? false,
                isRemovable: v.volumeIsRemovable ?? false,
                isEjectable: v.volumeIsEjectable ?? false,
                isReadOnly: v.volumeIsReadOnly ?? false,
                isRootVolume: v.volumeIsRootFileSystem ?? (url.path == "/")))
        }
        return result.sorted { a, b in
            if a.isRootVolume != b.isRootVolume { return a.isRootVolume }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
