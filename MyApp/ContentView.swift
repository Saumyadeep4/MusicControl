import SwiftUI

struct ContentView: View {
    @EnvironmentObject var player: PlayerStore
    @AppStorage("showSongInMenuBar") private var showSong = true
    @AppStorage("showArtInMenuBar") private var showArt = true
    @AppStorage("showNotch") private var showNotch = true

    @State private var showSettings = false
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var hoveringBar = false

    var body: some View {
        VStack(spacing: 18) {
            if player.hasTrack {
                artworkView
                titleBlock
                scrubber
                controls
            } else {
                emptyState
            }
            footer
            if showSettings { settingsPanel }
        }
        .padding(22)
        .frame(width: 320)
        .background { backdrop }
        .clipped()
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showSettings)
        .animation(.easeInOut(duration: 0.4), value: player.hasTrack)
    }

    // MARK: - Background

    private var backdrop: some View {
        ZStack {
            Color.black
            if let art = player.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.5)
                    .blur(radius: 60)
                    .saturation(1.5)
                    .opacity(0.75)
            } else {
                LinearGradient(colors: [.purple.opacity(0.35), .blue.opacity(0.25)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            Color.black.opacity(0.25)
        }
        .animation(.easeInOut(duration: 0.6), value: player.title)
    }

    // MARK: - Artwork

    private var artworkView: some View {
        Group {
            if let art = player.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [.purple.opacity(0.6), .blue.opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: 60))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: 240, height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .scaleEffect(player.isPlaying ? 1 : 0.92)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
    }

    // MARK: - Title

    private var subtitle: String {
        [player.album, player.playlist].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(player.title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text(player.artist)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            Text(player.source.rawValue.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Scrub bar

    private var scrubber: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let total = max(player.duration, 1)
                let current = scrubbing ? scrubValue : player.position
                let fraction = CGFloat(min(max(current / total, 0), 1))
                let active = hoveringBar || scrubbing
                let barHeight: CGFloat = active ? 8 : 5

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.2))
                        .frame(height: barHeight)
                    Capsule()
                        .fill(.white.opacity(0.95))
                        .frame(width: geo.size.width * fraction, height: barHeight)
                    Circle()
                        .fill(.white)
                        .frame(width: 13, height: 13)
                        .shadow(radius: 2)
                        .offset(x: geo.size.width * fraction - 6.5)
                        .opacity(active ? 1 : 0)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .animation(.easeOut(duration: 0.15), value: active)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubbing = true
                            player.isScrubbing = true
                            let p = min(max(value.location.x / geo.size.width, 0), 1)
                            scrubValue = Double(p) * total
                        }
                        .onEnded { value in
                            let p = min(max(value.location.x / geo.size.width, 0), 1)
                            player.seek(to: Double(p) * total)
                            scrubbing = false
                            player.isScrubbing = false
                        }
                )
            }
            .frame(height: 20)
            .onHover { hoveringBar = $0 }

            HStack {
                Text(format(scrubbing ? scrubValue : player.position))
                Spacer()
                Text(format(player.duration))
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 34) {
            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 22))
            }
            Button { player.playPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.black)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 22))
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 46))
                .foregroundStyle(.white.opacity(0.5))
            Text("Nothing playing")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("Start a song in Apple Music or Spotify")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))

            if !player.lastError.isEmpty {
                Text(player.lastError)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }

            Button("Allow access to Music & Spotify") { player.requestPermissions() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

            if !player.permissionStatus.isEmpty {
                Text(player.permissionStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Button("Open Automation settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.link)
            .font(.system(size: 10))
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 230)
    }

    // MARK: - Footer and settings

    private var footer: some View {
        HStack {
            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(showSettings ? .white : .white.opacity(0.5))
            }
            .help("Settings")
            Spacer()
            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .help("Quit")
        }
        .font(.system(size: 14))
        .buttonStyle(PressableStyle())
    }

    private var settingsPanel: some View {
        VStack(spacing: 10) {
            settingRow("Album art in menu bar", isOn: $showArt)
            settingRow("Song name in menu bar", isOn: $showSong)
            settingRow("Notch display", isOn: $showNotch)
        }
        .font(.system(size: 12))
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.08)))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func settingRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// Gives buttons a small "press" animation
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
