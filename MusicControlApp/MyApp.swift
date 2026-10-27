import SwiftUI

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = PlayerStore.shared
    @AppStorage("showSongInMenuBar") private var showSong = true
    @AppStorage("showArtInMenuBar") private var showArt = true
    @AppStorage("menuBarTextStyle") private var textStyle = 0   // 0 song - artist, 1 song only, 2 artist - song
    @AppStorage("menuBarMaxChars") private var maxChars = 28

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(player)
        } label: {
            HStack(spacing: 5) {
                if showArt, player.hasTrack, let art = player.menuBarArtwork {
                    Image(nsImage: art)
                } else {
                    Image(systemName: player.isPlaying ? "play.fill" : "music.note")
                }
                if showSong && player.hasTrack {
                    Text(menuBarText)
                }
            }
        }
        .menuBarExtraStyle(.window)
    }

    private var menuBarText: String {
        let full: String
        switch textStyle {
        case 1:  full = player.title
        case 2:  full = "\(player.artist) - \(player.title)"
        default: full = "\(player.title) - \(player.artist)"
        }
        let limit = max(maxChars, 12)
        return full.count > limit ? String(full.prefix(limit - 1)) + "…" : full
    }
}
