import SwiftUI

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var player = PlayerStore.shared
    @AppStorage("showSongInMenuBar") private var showSong = true
    @AppStorage("showArtInMenuBar") private var showArt = true

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
        let full = "\(player.title) - \(player.artist)"
        return full.count > 28 ? String(full.prefix(27)) + "…" : full
    }
}
