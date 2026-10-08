import SwiftUI
import AppKit
import Combine

@MainActor
final class PlayerStore: ObservableObject {
    static let shared = PlayerStore()
    @Published var title = ""
    @Published var artist = ""
    @Published var album = ""
    @Published var playlist = ""
    @Published var isPlaying = false
    @Published var hasTrack = false
    @Published var artwork: NSImage?
    @Published var menuBarArtwork: NSImage?
    @Published var duration: Double = 0
    @Published var position: Double = 0

    private var task: Task<Void, Never>?
    private var lastTrackKey = ""
    var isScrubbing = false

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
            set d to (duration of current track) as integer
            set pos to (player position) as integer
            set s to player state as string
            return t & "|||" & a & "|||" & al & "|||" & p & "|||" & s & "|||" & d & "|||" & pos
        end tell
        """

        guard let result = run(script)?.stringValue, result != "STOPPED" else {
            hasTrack = false
            return
        }

        let parts = result.components(separatedBy: "|||")
        guard parts.count == 7 else { return }

        title = parts[0]
        artist = parts[1]
        album = parts[2]
        playlist = parts[3]
        isPlaying = (parts[4] == "playing")
        duration = Double(parts[5]) ?? 0
        if !isScrubbing { position = Double(parts[6]) ?? 0 }
        hasTrack = true

        // Only reload artwork when the song changes
        let key = "\(parts[0])|\(parts[1])|\(parts[2])"
        if key != lastTrackKey {
            lastTrackKey = key
            loadArtwork()
        }
    }

    private func loadArtwork() {
        let script = """
        tell application "Music"
            try
                return raw data of artwork 1 of current track
            on error
                return missing value
            end try
        end tell
        """
        if let descriptor = run(script), let image = NSImage(data: descriptor.data) {
            artwork = image
            menuBarArtwork = Self.makeSmall(image)
        } else {
            artwork = nil
            menuBarArtwork = nil
        }
    }

    /// Shrinks the cover to a small rounded square for the menu bar
    private static func makeSmall(_ image: NSImage, size: CGFloat = 18) -> NSImage {
        let result = NSImage(size: NSSize(width: size, height: size))
        result.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    // MARK: - Controls

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }
    func seek(to seconds: Double) {
            let target = max(0, min(seconds, duration))
            position = target
            _ = run("tell application \"Music\" to set player position to \(target)")
        }

    private func command(_ cmd: String) {
        _ = run("tell application \"Music\" to \(cmd)")
        refresh()
    }

    // MARK: - AppleScript helper

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { print("AppleScript error:", error) }
        return result
    }
}
