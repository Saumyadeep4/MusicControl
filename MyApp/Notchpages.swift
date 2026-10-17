import SwiftUI

// MARK: - The pages the card (and the popover) can show

enum NotchPage: String, CaseIterable, Identifiable {
    case music
    case battery
    // Add new pages here (calendar, mirror, shelf...) as they get built.

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music:   return "Music"
        case .battery: return "Battery"
        }
    }

    var icon: String {
        switch self {
        case .music:   return "music.note"
        case .battery: return "battery.100"
        }
    }
}

/// Which pages can be presented right now. The popover keeps Music available while
/// idle; the hover card only includes it when there is a track to control.
@MainActor
func availableNotchPages(player: PlayerStore, includeIdleMusic: Bool = false) -> [NotchPage] {
    var pages: [NotchPage] = []
    if player.hasTrack || includeIdleMusic {
        pages.append(.music)
    }
    if FeatureAccess.shared.isActive(.battery) && BatteryStore.shared.hasBattery {
        pages.append(.battery)
    }
    return pages
}

// MARK: - Page switcher (small icon row, used in the popover)

struct NotchPageSwitcher: View {
    let pages: [NotchPage]
    let current: NotchPage
    let accent: Color
    let onSelect: (NotchPage) -> Void

    var body: some View {
        HStack(spacing: 18) {
            ForEach(pages) { page in
                Button {
                    onSelect(page)
                } label: {
                    Image(systemName: page.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color(for: page))
                        .frame(width: 28, height: 22)
                }
                .buttonStyle(.plain)
                .help(page.title)
            }
        }
        .frame(height: 26)
    }

    private func color(for page: NotchPage) -> Color {
        if page == current {
            return accent
        }
        return Color.white.opacity(0.4)
    }
}

// MARK: - Music page (the player inside the notch card)

struct NotchMusicPage: View {
    @EnvironmentObject var player: PlayerStore
    @ObservedObject private var features = FeatureAccess.shared
    @ObservedObject private var options = PlaybackOptionsStore.shared

    @State private var scrubbing = false
    @State private var scrubProgress: CGFloat = 0

    private var showsModes: Bool {
        features.isActive(.shuffleRepeat) && options.isSupported
    }

    var body: some View {
        Group {
            if player.hasTrack {
                playerContent
            } else {
                emptyContent
            }
        }
    }

    private var playerContent: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                artwork(size: 60, radius: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(player.artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Text(player.album)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            progressBar

            controls
        }
        .padding(.horizontal, 22)
        .animation(.easeInOut(duration: 0.35), value: player.accent)
    }

    private var emptyContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 34))
                .foregroundStyle(.white.opacity(0.55))
            Text("Nothing playing")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text("Start audio in Music, Spotify, or another supported app.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
    }

    private var progressBar: some View {
        VStack(spacing: 3) {
            GeometryReader { geo in
                let shown = scrubbing ? scrubProgress : progress
                ZStack(alignment: .leading) {
                    Capsule().fill(player.accent.opacity(0.25))
                        .frame(height: 4)
                    Capsule().fill(player.accent)
                        .frame(width: geo.size.width * shown, height: 4)
                }
                .frame(height: geo.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubbing = true
                            player.isScrubbing = true
                            scrubProgress = min(max(value.location.x / geo.size.width, 0), 1)
                        }
                        .onEnded { value in
                            let p = min(max(value.location.x / geo.size.width, 0), 1)
                            player.seek(to: Double(p) * player.duration)
                            scrubbing = false
                            player.isScrubbing = false
                        }
                )
            }
            .frame(height: 16)

            HStack {
                Text(format(scrubbing ? Double(scrubProgress) * player.duration : player.position))
                Spacer()
                Text(format(player.duration))
            }
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var controls: some View {
        HStack(spacing: 26) {
            if showsModes {
                ShuffleButton(active: player.accent, inactive: Color.white.opacity(0.4))
            }

            Button { player.previous() } label: { Image(systemName: "backward.fill") }

            Button { player.playPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(player.accent))
            }

            Button { player.next() } label: { Image(systemName: "forward.fill") }

            if showsModes {
                RepeatButton(active: player.accent, inactive: Color.white.opacity(0.4))
            }
        }
        .buttonStyle(PressableStyle())
        .font(.title3)
        .foregroundStyle(player.accent)
    }

    @ViewBuilder
    private func artwork(size: CGFloat, radius: CGFloat) -> some View {
        if let art = player.artwork {
            Image(nsImage: art)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: radius))
        } else {
            RoundedRectangle(cornerRadius: radius)
                .fill(Color.white.opacity(0.15))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(Color.white.opacity(0.7))
                )
        }
    }

    private var progress: CGFloat {
        guard player.duration > 0 else { return 0 }
        return CGFloat(min(player.position / player.duration, 1))
    }

    private func format(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Battery page (used in the notch and in the popover)

struct NotchBatteryPage: View {
    @ObservedObject private var battery = BatteryStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(battery.tint.opacity(0.16))
                    Image(systemName: battery.symbolName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(battery.tint)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(battery.percent)%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                        Text(battery.isCharging ? "CHARGING" : "BATTERY")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(battery.tint.opacity(0.9))
                    }
                    Text(battery.statusText)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { battery.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.white.opacity(0.45))
                    .help("Refresh battery")
            }

            levelBar

            HStack {
                Label(battery.onACPower ? "Power adapter connected" : "Running on battery",
                      systemImage: battery.onACPower ? "powerplug.fill" : "laptopcomputer")
                Spacer()
                if battery.lowPowerMode {
                    Label("Low Power", systemImage: "leaf.fill")
                        .foregroundStyle(Color.yellow)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.58))
        }
        .padding(.horizontal, 22)
    }

    private var levelBar: some View {
        GeometryReader { geo in
            let fraction = CGFloat(battery.percent) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.15))
                Capsule().fill(battery.tint)
                    .frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 6)
    }
}
