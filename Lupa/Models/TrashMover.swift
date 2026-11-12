import Foundation

/// Moves to the Trash what belongs to the system (root), such as apps installed by
/// a .pkg in /Applications/<folder>. Legroom never asks for or stores a password: Finder
/// asks, in macOS's own authorization window, just like dragging to the Trash.
/// The item lands in the Trash with "Put Back" working.
enum TrashMover {
    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain, [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code) { return true }
        if let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError, u.domain == NSPOSIXErrorDomain, [Int(EACCES), Int(EPERM)].contains(u.code) { return true }
        return ns.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(ns.code)
    }

    /// Asks Finder to move everything at once (a single password prompt).
    /// Returns when Finder finishes or the person cancels.
    static func trashWithFinder(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        let script = """
        on run argv
            set targets to {}
            repeat with p in argv
                set end of targets to (POSIX file (p as text) as alias)
            end repeat
            with timeout of 600 seconds
                tell application "Finder" to delete targets
            end timeout
        end run
        """
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script] + urls.map(\.path)
            p.standardOutput = FileHandle.nullDevice
            let err = Pipe()
            p.standardError = err
            p.terminationHandler = { proc in
                let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if proc.terminationStatus != 0 { Trail.note("Finder didn't move: \(msg.trimmingCharacters(in: .whitespacesAndNewlines))") }
                c.resume()
            }
            do { try p.run() } catch { c.resume() }
        }
    }
}
