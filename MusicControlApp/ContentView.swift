import SwiftUI

struct ContentView: View {
    @EnvironmentObject var player: PlayerStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var updater = UpdateChecker.shared
    @ObservedObject private var features = FeatureAccess.shared
    @ObservedObject private var battery = BatteryStore.shared
    @ObservedObject private var options = PlaybackOptionsStore.shared

    @State private var selectedPage: NotchPage = .music

    @State private var scrubbing = false
    @State private var scrubValue: Double = 0
    @State private var hoveringBar = false
    @State private var showingLyrics = false

    private var showsModes: Bool {
        features.isActive(.shuffleRepeat) && options.isSupported
    }

    var body: some View {
        let pages = availableNotchPages(player: player, includeIdleMusic: true)
        let current = currentPage(in: pages)

        return VStack(spacing: 18) {
            pageContent(current)

            if pages.count > 1 {
                NotchPageSwitcher(pages: pages, current: current, accent: player.accent) {
                    selectedPage = $0
                }
            }
            footer
        }
        .padding(22)
        .frame(width: 320)
        .background { backdrop }
        .clipped()
        .environment(\.colorScheme, .dark)
        // Keyboard: Space plays or pauses, the arrow keys skip
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            player.playPause()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            player.previous()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            player.next()
            return .handled
        }
        .onChange(of: pages) { _, newPages in
            if !newPages.contains(selectedPage) {
                selectedPage = newPages.first ?? .music
            }
        }
    }

    @ViewBuilder
    private func pageContent(_ page: NotchPage) -> some View {
        switch page {
        case .music:
            if player.hasTrack {
                VStack(spacing: 18) {
                    artworkView
                    titleBlock
                    scrubber
                    controls
                    if features.isActive(.audioControl) {
                        AudioControlBar()
                    }
                }
            } else {
                emptyState
            }
        case .battery:
            NotchBatteryPage()
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func currentPage(in pages: [NotchPage]) -> NotchPage {
        if pages.contains(selectedPage) {
            return selectedPage
        }
        return pages.first ?? .music
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
        .id("\(player.title)|\(player.artist)")
        .transition(.opacity)
        .frame(width: 240, height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .scaleEffect(player.isPlaying ? 1 : 0.92)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: player.isPlaying)
        .animation(.easeInOut(duration: 0.3), value: player.title)
        .onTapGesture { openSourceApp() }
        .help(player.source.appName.isEmpty ? "" : "Open \(player.source.appName)")
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Album artwork")
    }

    // MARK: - Title

    private var subtitle: String {
        [player.album, player.playlist].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            MarqueeText(text: player.title,
                        font: .system(size: 19, weight: .bold, design: .rounded),
                        color: Color.white,
                        alignment: .center)
            MarqueeText(text: player.artist,
                        font: .system(size: 14, weight: .medium),
                        color: Color.white.opacity(0.75),
                        alignment: .center)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                Text(player.sourceLabel.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.35))
                EqualizerBars(isPlaying: player.isPlaying, color: player.accent.opacity(0.7), height: 9)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .contextMenu {
            Button("Copy song and artist") { copySongInfo() }
        }
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback position")
            .accessibilityValue("\(format(player.position)) of \(format(player.duration))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: player.seek(to: player.position + 10)
                case .decrement: player.seek(to: player.position - 10)
                @unknown default: break
                }
            }

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
        HStack(spacing: 24) {
            if showsModes {
                ShuffleButton(active: player.accent, inactive: Color.white.opacity(0.4))
            }

            Button { player.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 22))
            }
            .accessibilityLabel("Previous track")

            Button { player.playPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.black)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button { player.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 22))
            }
            .accessibilityLabel("Next track")

            if showsModes {
                RepeatButton(active: player.accent, inactive: Color.white.opacity(0.4))
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Empty state

    /// True when macOS has refused (or is still waiting on) permission for Music or Spotify
    private var needsPermissionHelp: Bool {
        let status = player.permissionStatus
        return status.contains("denied") || status.contains("waiting") || player.lastError.contains("-1743")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 46))
                .foregroundStyle(.white.opacity(0.5))
            Text("Nothing playing")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("Start a song in Apple Music, Spotify or a browser")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)

            if needsPermissionHelp {
                permissionHelpCard
            } else {
                VStack(spacing: 6) {
                    Button("Having trouble?") { openSettings(page: .music) }
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                    if !player.lastError.isEmpty {
                        Text(player.lastError)
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 230)
    }

    private var permissionHelpCard: some View {
        VStack(spacing: 8) {
            Label("MusicControl needs permission", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.yellow)
            Text("macOS blocked access to your music app. Click Allow access and choose OK, or switch MusicControl on under Automation in System Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Allow access") { player.requestPermissions() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Open settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
            if !player.permissionStatus.isEmpty {
                Text(player.permissionStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            if !player.lastError.isEmpty {
                Text(player.lastError)
                    .font(.system(size: 10))
                    .foregroundStyle(.red.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button { openSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .help("Settings")
            .accessibilityLabel("Settings")

            if features.isActive(.sleepTimer) && player.hasTrack {
                SleepTimerButton()
            }

            if player.hasTrack {
                Button { player.toggleFavorite() } label: {
                    Image(systemName: "heart")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .help(player.source == .appleMusic ? "Favorite in Apple Music" : "Favorites are available in Apple Music only")
                .accessibilityLabel("Favorite current track")

                Button { showingLyrics = true } label: {
                    Image(systemName: "text.quote")
                        .foregroundStyle(.white.opacity(0.5))
                }
                .help("Lyrics")
                .accessibilityLabel("Show lyrics")
            }

            Spacer()

            if updater.hasUpdate {
                Button {
                    openSettings(page: .updates)
                } label: {
                    Text("Update available")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.85)))
                        .foregroundStyle(.black)
                }
            }

            Spacer()

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
                    .foregroundStyle(.white.opacity(0.5))
            }
            .help("Quit")
            .accessibilityLabel("Quit MusicControl")
        }
        .font(.system(size: 14))
        .buttonStyle(PressableStyle())
        .sheet(isPresented: $showingLyrics) {
            LyricsSheet(title: player.title, artist: player.artist, lyrics: player.lyrics, isLoading: player.lyricsLoading, position: player.position)
        }
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Click the artwork to bring the music app to the front (Music and Spotify)
    private func openSourceApp() {
        let id = player.source.bundleID
        guard !id.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func copySongInfo() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("\(player.title) - \(player.artist)", forType: .string)
    }

    private func openSettings(page: SettingsView.Page? = nil) {
        // A MenuBarExtra window can otherwise stay above Settings and hide it.
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            SettingsWindowController.shared.show(page: page)
        }
    }
}

private struct LyricsSheet: View {
    let title: String
    let artist: String
    let lyrics: String
    let isLoading: Bool
    let position: Double
    @Environment(\.dismiss) private var dismiss

    private struct Line: Identifiable {
        let id = UUID()
        let time: Double?
        let text: String
    }

    private var lines: [Line] {
        lyrics.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            let value = String(raw)
            let pattern = #"^\[(\d{2}):(\d{2}(?:\.\d{2})?)\]"#
            guard let match = try? NSRegularExpression(pattern: pattern).firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  let minutesRange = Range(match.range(at: 1), in: value),
                  let secondsRange = Range(match.range(at: 2), in: value) else {
                return Line(time: nil, text: value.trimmingCharacters(in: .whitespaces))
            }
            let time = (Double(value[minutesRange]) ?? 0) * 60 + (Double(value[secondsRange]) ?? 0)
            let text = String(value[Range(match.range, in: value)!.upperBound...]).trimmingCharacters(in: .whitespaces)
            return Line(time: time, text: text)
        }.filter { !$0.text.isEmpty }
    }

    private var currentLineIndex: Int? {
        lines.lastIndex { ($0.time ?? .infinity) <= position }
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(artist).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
            }
            if isLoading {
                ProgressView("Finding lyrics…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("Lyrics unavailable", systemImage: "text.quote",
                                       description: Text("No lyrics were found for this track."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 14) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                                Text(line.text)
                                    .font(.system(size: 19, weight: index == currentLineIndex ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(index == currentLineIndex ? Color.white : Color.white.opacity(0.35))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .id(index)
                            }
                        }.padding(.horizontal, 20).padding(.vertical, 110)
                    }
                    .onChange(of: currentLineIndex) { _, index in
                        if let index { withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(index, anchor: .center) } }
                    }
                }
                .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
            }
        }
        .padding(20)
        .frame(width: 420, height: 520)
        .background {
            LinearGradient(colors: [Color.indigo.opacity(0.24), Color.black.opacity(0.95)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
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
