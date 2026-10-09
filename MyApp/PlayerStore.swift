import SwiftUI
import AppKit
import Combine
import ApplicationServices

enum MusicSource: String, CaseIterable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"

    var appName: String {
        switch self {
        case .appleMusic: return "Music"
        case .spotify: return "Spotify"
        }
    }

    var bundleID: String {
        switch self {
        case .appleMusic: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }
}

struct TrackInfo {
    var title: String
    var artist: String
    var album: String
    var playlist: String
    var isPlaying: Bool
    var duration: Double
    var position: Double
}

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
    @Published var source: MusicSource = .appleMusic
    @Published var lastError = ""
    @Published var permissionStatus = ""

    var isScrubbing = false

    private var task: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var lastTrackKey = ""

    init() {
        refresh()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
        requestPermissions()
    }

    // MARK: - Permissions

    /// Asks macOS for permission to control each music app that is open,
    /// which shows the "wants to control..." prompt if it hasn't been answered.
    func requestPermissions() {
        let targets = MusicSource.allCases.map {
            (name: $0.rawValue, id: $0.bundleID, running: isRunning($0))
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var lines: [String] = []
            for t in targets {
                guard t.running else {
                    lines.append("\(t.name): not open (open it, then tap Allow again)")
                    continue
                }
                let status = PlayerStore.askPermission(bundleID: t.id)
                switch status {
                case 0:     lines.append("\(t.name): allowed")
                case -1743: lines.append("\(t.name): denied (error -1743)")
                case -1744: lines.append("\(t.name): waiting for your approval (error -1744)")
                default:    lines.append("\(t.name): status \(status)")
                }
            }
            let text = lines.joined(separator: "\n")
            Task { @MainActor in self?.permissionStatus = text }
        }
    }

    nonisolated static func askPermission(bundleID: String) -> Int {
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        guard let desc = target.aeDesc else { return -50 }
        return Int(AEDeterminePermissionToAutomateTarget(desc, typeWildCard, typeWildCard, true))
    }

    // MARK: - Deciding which app to show

    private func isRunning(_ source: MusicSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty
    }

    func refresh() {
        var found: [(source: MusicSource, info: TrackInfo)] = []
        for s in MusicSource.allCases where isRunning(s) {
            if let info = readTrack(from: s) {
                found.append((s, info))
            }
        }

        guard !found.isEmpty else {
            hasTrack = false
            return
        }

        let playing = found.filter { $0.info.isPlaying }
        let chosen: (source: MusicSource, info: TrackInfo)
        if playing.count == 1 {
            chosen = playing[0]
        } else if let current = found.first(where: { $0.source == source }) {
            chosen = current          // stay on the one we were showing
        } else {
            chosen = found[0]
        }
        apply(chosen.source, chosen.info)
    }

    private func apply(_ s: MusicSource, _ t: TrackInfo) {
        source = s
        title = t.title
        artist = t.artist
        album = t.album
        playlist = t.playlist
        isPlaying = t.isPlaying
        duration = t.duration
        if !isScrubbing { position = t.position }
        hasTrack = true
        lastError = ""

        // Only reload artwork when the song (or the app) changes
        let key = "\(s.rawValue)|\(t.title)|\(t.artist)|\(t.album)"
        if key != lastTrackKey {
            lastTrackKey = key
            loadArtwork(for: s, key: key)
        }
    }

    // MARK: - Reading a track

    private func readTrack(from source: MusicSource) -> TrackInfo? {
        let script: String
        switch source {
        case .appleMusic:
            script = """
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
        case .spotify:
            script = """
            tell application "Spotify"
                if player state is stopped then return "STOPPED"
                set t to name of current track
                set a to artist of current track
                set al to album of current track
                set d to (duration of current track) as integer
                set pos to (player position) as integer
                set s to "paused"
                if player state is playing then set s to "playing"
                return t & "|||" & a & "|||" & al & "|||" & "" & "|||" & s & "|||" & d & "|||" & pos
            end tell
            """
        }

        guard let result = run(script)?.stringValue else { return nil }
        if result == "STOPPED" { return nil }
        let parts = result.components(separatedBy: "|||")
        guard parts.count == 7 else {
            lastError = "\(source.rawValue) returned unexpected data: \(result)"
            return nil
        }

        var duration = Double(parts[5]) ?? 0
        // Spotify reports the length in milliseconds
        if source == .spotify && duration > 10_000 { duration /= 1000 }

        return TrackInfo(title: parts[0],
                         artist: parts[1],
                         album: parts[2],
                         playlist: parts[3],
                         isPlaying: parts[4] == "playing",
                         duration: duration,
                         position: Double(parts[6]) ?? 0)
    }

    // MARK: - Artwork

    private func loadArtwork(for source: MusicSource, key: String) {
        artworkTask?.cancel()

        switch source {
        case .appleMusic:
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

        case .spotify:
            artwork = nil
            menuBarArtwork = nil

            let script = """
            tell application "Spotify"
                try
                    return artwork url of current track
                on error
                    return ""
                end try
            end tell
            """
            guard let urlString = run(script)?.stringValue,
                  !urlString.isEmpty,
                  let url = URL(string: urlString) else { return }

            artworkTask = Task { [weak self] in
                guard let result = try? await URLSession.shared.data(from: url),
                      let image = NSImage(data: result.0) else { return }
                guard let self, !Task.isCancelled, self.lastTrackKey == key else { return }
                self.artwork = image
                self.menuBarArtwork = Self.makeSmall(image)
            }
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

    // MARK: - Controls (sent to whichever app is showing)

    func playPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    func seek(to seconds: Double) {
        let target = max(0, min(seconds, duration))
        position = target
        _ = run("tell application \"\(source.appName)\" to set player position to \(Int(target))")
    }

    private func command(_ cmd: String) {
        _ = run("tell application \"\(source.appName)\" to \(cmd)")
        refresh()
    }

    // MARK: - AppleScript helper

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            print("AppleScript error:", error)
            let number = (error.object(forKey: "NSAppleScriptErrorNumber") as? Int) ?? 0
            let message = (error.object(forKey: "NSAppleScriptErrorMessage") as? String) ?? "unknown"
            lastError = "Error \(number): \(message)"
        }
        return result
    }
}
