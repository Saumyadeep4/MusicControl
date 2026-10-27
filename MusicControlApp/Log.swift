import os
import Foundation

/// Central place for log messages. Open Console.app and search for "MusicControl" to read them.
enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "MusicControl"

    static let script = Logger(subsystem: subsystem, category: "AppleScript")
    static let permissions = Logger(subsystem: subsystem, category: "Permissions")
}
