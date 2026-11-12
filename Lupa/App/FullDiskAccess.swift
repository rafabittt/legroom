import Foundation

/// Whether Legroom has Full Disk Access. With no public API to ask, it tries
/// opening files macOS only lets you read with that access (the system's
/// permissions database and the Safari folder). Nothing is read beyond opening them.
enum FullDiskAccess {
    static var granted: Bool {
        let probes = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db",
            NSHomeDirectory() + "/Library/Safari",
        ]
        for path in probes where FileManager.default.fileExists(atPath: path) {
            let fd = open(path, O_RDONLY)
            if fd >= 0 { close(fd); return true }
            if errno == EPERM || errno == EACCES { continue }
        }
        return false
    }
}
