//
//  Playbackoptions.swift
//  Untitled Project
//
//  Created by Saumyadeep Chakraborty on 16-10-2026.
//

import SwiftUI
import AppKit
import Combine

enum RepeatSetting: String {
    case off
    case all
    case one
}

/// Shuffle and repeat for Apple Music and Spotify (both can be scripted).
/// Browsers and other apps don't offer these controls, so `isSupported` is false for them
/// and the buttons stay hidden.
@MainActor
final class PlaybackOptionsStore: ObservableObject {
    static let shared = PlaybackOptionsStore()

    @Published private(set) var shuffleOn = false
    @Published private(set) var repeatSetting: RepeatSetting = .off
    @Published private(set) var isSupported = false

    private var pollTask: Task<Void, Never>?

    private init() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // MARK: - Reading

    func refresh() {
        let player = PlayerStore.shared
        guard player.hasTrack else {
            isSupported = false
            return
        }

        switch player.source {
        case .appleMusic:
            readAppleMusic()
        case .spotify:
            readSpotify()
        case .system:
            isSupported = false
        }
    }

    private func isRunning(_ source: MusicSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty
    }

    private func readAppleMusic() {
        // Never run a script against an app that is closed, because that would launch it
        guard isRunning(.appleMusic) else {
            isSupported = false
            return
        }
        let script = """
        tell application "Music"
            return (shuffle enabled as string) & "|" & (song repeat as string)
        end tell
        """
        guard let text = run(script)?.stringValue else {
            isSupported = false
            return
        }
        let parts = text.components(separatedBy: "|")
        guard parts.count == 2 else {
            isSupported = false
            return
        }
        shuffleOn = parts[0] == "true"
        repeatSetting = RepeatSetting(rawValue: parts[1]) ?? .off
        isSupported = true
    }

    private func readSpotify() {
        guard isRunning(.spotify) else {
            isSupported = false
            return
        }
        let script = """
        tell application "Spotify"
            return (shuffling as string) & "|" & (repeating as string)
        end tell
        """
        guard let text = run(script)?.stringValue else {
            isSupported = false
            return
        }
        let parts = text.components(separatedBy: "|")
        guard parts.count == 2 else {
            isSupported = false
            return
        }
        shuffleOn = parts[0] == "true"
        repeatSetting = parts[1] == "true" ? .all : .off
        isSupported = true
    }

    // MARK: - Changing

    func toggleShuffle() {
        let newValue = !shuffleOn
        switch PlayerStore.shared.source {
        case .appleMusic:
            _ = run("tell application \"Music\" to set shuffle enabled to \(newValue)")
        case .spotify:
            _ = run("tell application \"Spotify\" to set shuffling to \(newValue)")
        case .system:
            return
        }
        shuffleOn = newValue
    }

    /// Apple Music cycles off, all, one. Spotify can only switch repeat on or off.
    func cycleRepeat() {
        switch PlayerStore.shared.source {
        case .appleMusic:
            let next: RepeatSetting
            switch repeatSetting {
            case .off: next = .all
            case .all: next = .one
            case .one: next = .off
            }
            _ = run("tell application \"Music\" to set song repeat to \(next.rawValue)")
            repeatSetting = next
        case .spotify:
            let turnOn = repeatSetting == .off
            _ = run("tell application \"Spotify\" to set repeating to \(turnOn)")
            repeatSetting = turnOn ? .all : .off
        case .system:
            return
        }
    }

    // MARK: - AppleScript helper

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { print("AppleScript error:", error) }
        return result
    }
}

// MARK: - Buttons (used next to the play controls)

struct ShuffleButton: View {
    @ObservedObject private var options = PlaybackOptionsStore.shared
    let active: Color
    let inactive: Color

    var body: some View {
        Button { options.toggleShuffle() } label: {
            Image(systemName: "shuffle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(options.shuffleOn ? active : inactive)
                .frame(width: 26, height: 26)
        }
        .help(options.shuffleOn ? "Shuffle: on" : "Shuffle: off")
    }
}

struct RepeatButton: View {
    @ObservedObject private var options = PlaybackOptionsStore.shared
    let active: Color
    let inactive: Color

    private var symbol: String {
        options.repeatSetting == .one ? "repeat.1" : "repeat"
    }

    private var helpText: String {
        switch options.repeatSetting {
        case .off: return "Repeat: off"
        case .all: return "Repeat: all"
        case .one: return "Repeat: one song"
        }
    }

    var body: some View {
        Button { options.cycleRepeat() } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(options.repeatSetting == .off ? inactive : active)
                .frame(width: 26, height: 26)
        }
        .help(helpText)
    }
}
