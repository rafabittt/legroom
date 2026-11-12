import Foundation
import os

/// Trail of what the app did (v9.1), written to the system log at the "notice" level,
/// which macOS keeps on disk. Useful for understanding a crash that can't be
/// reproduced:
///   log show --last 1h --predicate 'subsystem == "com.rafabitt.legroom" AND category == "trail"'
/// Only actions and screens; never paths to the user's files.
enum Trail {
    private static let logger = Logger(subsystem: "com.rafabitt.legroom", category: "trail")
    static func note(_ s: String) { logger.notice("\(s, privacy: .public)") }
}
