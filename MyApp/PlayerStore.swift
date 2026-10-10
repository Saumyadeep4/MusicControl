import SwiftUI
import AppKit
import Combine
import ApplicationServices
import MediaRemoteAdapter

enum MusicSource: String {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case system = "Now Playing"

    /// Apps we talk to directly with AppleScript (richer info, e.g. playlist names)
    static let scriptable: [MusicSource] = [.appleMusic, .spotify]

    var appName: String {
        switch self {
        case .appleMusic: return "Music"
        case .spotify: return "Spotify"
        case .system: return ""
        }
    }

    var bundleID: String {
        switch self {
        case .appleMusic: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        case .system: return ""
        }
    }
}

/// Our own simple copy of a track. (Named differently from the package's own TrackInfo.)
struct TrackSnapshot {
    var title: String
    var artist: String
    var album: String
    var playlist: String
    var isPlaying: Bool
    var duration: Double
    var position: Double
}

/// What the system-wide "Now Playing" feed reports (any app, including browsers)
struct SystemMedia: @unchecked Sendable {
    var snapshot: TrackSnapshot
    var appName: String
    var bundleID: String
    var artwork: NSImage?
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
    @Published var artwork: NSImage? {
        didSet { accent = artwork.map { Self.accentColor(from: $0) } ?? .white }
    }
    /// A bright colour taken from the cover, used for buttons and the progress bar
    @Published var accent: Color = .white
    @Published var menuBarArtwork: NSImage?
    @Published var duration: Double = 0
    @Published var position: Double = 0
    @Published var source: MusicSource = .appleMusic
    @Published var sourceLabel = "Apple Music"
    @Published var lastError = ""
    @Published var permissionStatus = ""

    var isScrubbing = false

    private var task: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var lastTrackKey = ""

    // System-wide Now Playing
    private let mediaController = MediaController()
    private var systemMedia: SystemMedia?
    private var systemReceivedAt = Date()

    private var showSystemMedia: Bool {
        UserDefaults.standard.object(forKey: "showSystemMedia") as? Bool ?? true
    }

    init() {
        refresh()
        startSystemListener()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
        requestPermissions()
    }

    // MARK: - System-wide Now Playing (browsers, other players)

    private func startSystemListener() {
        mediaController.onTrackInfoReceived = { @Sendable [weak self] info in
            let media = PlayerStore.makeSystemMedia(from: info)
            Task { @MainActor in self?.handleSystem(media) }
        }
        mediaController.onListenerTerminated = { @Sendable [weak self] in
            Task { @MainActor in
                self?.handleSystem(nil)
                try? await Task.sleep(for: .seconds(1))
                self?.mediaController.startListening()
            }
        }
        mediaController.startListening()
    }

    nonisolated private static func makeSystemMedia(from info: TrackInfo?) -> SystemMedia? {
        guard let p = info?.payload,
              let title = p.title, !title.isEmpty else { return nil }

        let playing = p.isPlaying ?? ((p.playbackRate ?? 0) > 0)
        let snapshot = TrackSnapshot(
            title: title,
            artist: p.artist ?? "",
            album: p.album ?? "",
            playlist: "",
            isPlaying: playing,
            duration: (p.durationMicros ?? 0) / 1_000_000,
            position: p.currentElapsedTime ?? ((p.elapsedTimeMicros ?? 0) / 1_000_000)
        )
        return SystemMedia(snapshot: snapshot,
                           appName: p.applicationName ?? "Now Playing",
                           bundleID: p.bundleIdentifier ?? "",
                           artwork: p.artwork)
    }

    private func handleSystem(_ media: SystemMedia?) {
        systemMedia = media
        systemReceivedAt = Date()
        refresh()

        // Artwork can arrive a moment after the title
        if source == .system, let art = media?.artwork {
            artwork = art
            menuBarArtwork = Self.makeSmall(art)
        }
    }

    /// The system track, with the position moved forward since the last update
    private func currentSystemSnapshot() -> TrackSnapshot? {
        guard let media = systemMedia else { return nil }
        var t = media.snapshot
        if t.isPlaying {
            t.position += Date().timeIntervalSince(systemReceivedAt)
        }
        if t.duration > 0 { t.position = min(t.position, t.duration) }
        return t
    }

    // MARK: - Permissions (AppleScript apps only)

    func requestPermissions() {
        let targets = MusicSource.scriptable.map {
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

    // MARK: - Deciding what to show

    private func isRunning(_ source: MusicSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty
    }

    func refresh() {
        var found: [(source: MusicSource, info: TrackSnapshot, label: String)] = []

        for s in MusicSource.scriptable where isRunning(s) {
            if let info = readTrack(from: s) {
                found.append((s, info, s.rawValue))
            }
        }

        if showSystemMedia, let media = systemMedia, let info = currentSystemSnapshot() {
            // Apple Music and Spotify are already covered above with richer data
            let alreadyCovered = found.contains { $0.source.bundleID == media.bundleID }
            if !alreadyCovered {
                found.append((.system, info, media.appName))
            }
        }

        guard !found.isEmpty else {
            hasTrack = false
            return
        }

        let playing = found.filter { $0.info.isPlaying }
        let chosen: (source: MusicSource, info: TrackSnapshot, label: String)
        if playing.count == 1 {
            chosen = playing[0]
        } else if let current = found.first(where: { $0.source == source }) {
            chosen = current          // stay on the one we were showing
        } else {
            chosen = found[0]
        }
        apply(chosen.source, chosen.info, label: chosen.label)
    }

    private func apply(_ s: MusicSource, _ t: TrackSnapshot, label: String) {
        source = s
        sourceLabel = label
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
        let key = "\(label)|\(t.title)|\(t.artist)|\(t.album)"
        if key != lastTrackKey {
            lastTrackKey = key
            loadArtwork(for: s, key: key)
        }
    }

    // MARK: - Reading a track (AppleScript apps)

    private func readTrack(from source: MusicSource) -> TrackSnapshot? {
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
        case .system:
            return nil
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

        return TrackSnapshot(title: parts[0],
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

        case .system:
            if let art = systemMedia?.artwork {
                artwork = art
                menuBarArtwork = Self.makeSmall(art)
            } else {
                artwork = nil
                menuBarArtwork = nil
            }
        }
    }

    /// Finds the cover's most prominent colour and makes sure it is bright
    /// enough to read on a pure black background. Grey covers fall back to white.
    private static func accentColor(from image: NSImage) -> Color {
        let size = 24
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .white }

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress,
                                      width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return .white }

        // Group the colourful pixels into 12 hue buckets and keep the heaviest one
        let bins = 12
        var weight = [Double](repeating: 0, count: bins)
        var sumHue = [Double](repeating: 0, count: bins)
        var sumSat = [Double](repeating: 0, count: bins)
        var sumVal = [Double](repeating: 0, count: bins)

        for i in 0..<(size * size) {
            let r = Double(pixels[i * 4]) / 255
            let g = Double(pixels[i * 4 + 1]) / 255
            let b = Double(pixels[i * 4 + 2]) / 255
            let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
            guard mx > 0.15, d > 0.12 else { continue }   // skip near-black and grey pixels

            let sat = d / mx
            var hue: Double
            if mx == r {
                hue = ((g - b) / d).truncatingRemainder(dividingBy: 6)
            } else if mx == g {
                hue = (b - r) / d + 2
            } else {
                hue = (r - g) / d + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }

            let w = sat * mx
            let bin = min(Int(hue * Double(bins)), bins - 1)
            weight[bin] += w
            sumHue[bin] += hue * w
            sumSat[bin] += sat * w
            sumVal[bin] += mx * w
        }

        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }),
              weight[best] > 2 else { return .white }

        let hue = sumHue[best] / weight[best]
        let sat = min(max(sumSat[best] / weight[best], 0.5), 0.9)
        let val = max(sumVal[best] / weight[best], 0.9)
        return Color(hue: hue, saturation: sat, brightness: val)
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

    // MARK: - Controls (sent to whichever source is showing)

    func playPause() {
        if source == .system {
            mediaController.togglePlayPause()
        } else {
            command("playpause")
        }
    }

    func next() {
        if source == .system {
            mediaController.nextTrack()
        } else {
            command("next track")
        }
    }

    func previous() {
        if source == .system {
            mediaController.previousTrack()
        } else {
            command("previous track")
        }
    }

    func seek(to seconds: Double) {
        let target = max(0, min(seconds, duration))
        position = target
        if source == .system {
            mediaController.setTime(seconds: target)
            systemMedia?.snapshot.position = target
            systemReceivedAt = Date()
        } else {
            _ = run("tell application \"\(source.appName)\" to set player position to \(Int(target))")
        }
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
