import SwiftUI
import AppKit
import Combine

@MainActor
final class PlayerStore: ObservableObject {
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var playlist = ""
    @Published var isPlaying = false
    @Published var hasTrack = false

    private var task: Task<Void, Never>?

    init() {
        refresh()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
    }

    // MARK: - Reading what's playing

    private var musicIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").isEmpty
    }

    func refresh() {
        guard musicIsRunning else {
            hasTrack = false
            return
        }

        let script = """
        tell application "Music"
            if player state is stopped then return "STOPPED"
            set t to name of current track
            set a to artist of current track
            set al to album of current track
            set p to ""
            try
                set p to name of current playlist
            end try
            set s to player state as string
            return t & "|||" & a & "|||" & al & "|||" & p & "|||" & s
        end tell
        """

        guard let result = run(script), result != "STOPPED" else {
            hasTrack = false
            return
        }

        let parts = result.components(separatedBy: "|||")
        guard parts.count == 5 else { return }

        title = parts[0]
        artist = parts[1]
        album = parts[2]
        playlist = parts[3]
        isPlaying = (parts[4] == "playing")
        hasTrack = true
    }

    // MARK: - Controls

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    private func command(_ cmd: String) {
        _ = run("tell application \"Music\" to \(cmd)")
        refresh()
    }

    // MARK: - AppleScript helper

    private func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { print("AppleScript error:", error) }
        return result?.stringValue
    }
}
