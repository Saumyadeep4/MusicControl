import SwiftUI
import AppKit
import Combine

// MARK: - Sizes shared by the window and the view

enum NotchMetrics {
    static let expandedSize = CGSize(width: 380, height: 207)
    static let panelSize = CGSize(width: 400, height: 222)
}

final class NotchState: ObservableObject {
    @Published var expanded = false
}

// MARK: - The black notch shape (flat top, rounded bottom)

struct NotchShape: Shape {
    var bottomRadius: CGFloat

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(bottomRadius, rect.height / 2, rect.width / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                       control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                       control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - The notch UI

struct NotchView: View {
    @EnvironmentObject var player: PlayerStore
    @ObservedObject var state: NotchState
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool

    @State private var scrubbing = false
    @State private var scrubProgress: CGFloat = 0

    var body: some View {
        NotchShape(bottomRadius: state.expanded ? 26 : 10)
            .fill(Color.black)
            .frame(width: state.expanded ? NotchMetrics.expandedSize.width : notchWidth,
                   height: state.expanded ? NotchMetrics.expandedSize.height : notchHeight)
            .overlay(alignment: .top) {
                if state.expanded {
                    expandedContent.transition(.opacity)
                }
            }
            // Draw nothing while collapsed (on every Mac). The black card only
            // appears when the cursor opens it, growing out of the notch area.
            .opacity(state.expanded ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: state.expanded)
            .ignoresSafeArea()
    }

    private var expandedContent: some View {
        VStack(spacing: 10) {
            // Keeps everything below the physical notch
            Spacer().frame(height: notchHeight)

            if player.hasTrack {
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

                HStack(spacing: 34) {
                    Button { player.previous() } label: { Image(systemName: "backward.fill") }
                    Button { player.playPause() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(player.accent))
                    }
                    Button { player.next() } label: { Image(systemName: "forward.fill") }
                }
                .buttonStyle(PressableStyle())
                .font(.title3)
                .foregroundStyle(player.accent)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
        .animation(.easeInOut(duration: 0.35), value: player.accent)
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
                .overlay(Image(systemName: "music.note")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.white.opacity(0.7)))
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

// MARK: - The floating window

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Lets the window sit over the menu bar area
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class NotchController {
    private let panel: NotchPanel
    private let state: NotchState
    private let screen: NSScreen
    private let notchSize: CGSize
    private let player: PlayerStore
    private var pollTask: Task<Void, Never>?

    init(player: PlayerStore) {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        // Work out the real notch size (fallback for Macs without a notch)
        let hasNotch = screen.safeAreaInsets.top > 0
        var size = CGSize(width: 180, height: 28)
        if hasNotch,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            size = CGSize(width: screen.frame.width - left.width - right.width,
                          height: screen.safeAreaInsets.top)
        }

        let state = NotchState()
        let panelSize = NotchMetrics.panelSize
        let frame = NSRect(x: screen.frame.midX - panelSize.width / 2,
                           y: screen.frame.maxY - panelSize.height,
                           width: panelSize.width,
                           height: panelSize.height)

        let panel = NotchPanel(contentRect: frame,
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered,
                               defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let host = NSHostingView(rootView:
            NotchView(state: state,
                      notchWidth: size.width,
                      notchHeight: size.height,
                      hasNotch: hasNotch)
                .environmentObject(player)
        )
        panel.contentView = host
        panel.setFrame(frame, display: true)

        self.screen = screen
        self.notchSize = size
        self.state = state
        self.panel = panel
        self.player = player

        // Starts hidden. It only appears once there is media to control.
        panel.orderOut(nil)

        // Check the mouse position several times a second
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                self?.updateHover()
            }
        }
    }

    private var enabled: Bool {
        UserDefaults.standard.object(forKey: "showNotch") as? Bool ?? true
    }

    private func updateHover() {
        // No media loaded (or notch turned off): the notch window is not on screen at all,
        // so hovering over the notch does nothing.
        guard enabled, player.hasTrack else {
            if panel.isVisible { panel.orderOut(nil) }
            state.expanded = false
            panel.ignoresMouseEvents = true
            return
        }
        if !panel.isVisible { panel.orderFrontRegardless() }

        let mouse = NSEvent.mouseLocation
        let f = screen.frame
        let rect: NSRect

        if state.expanded {
            // Stay open while the cursor is anywhere on the card
            let s = NotchMetrics.expandedSize
            rect = NSRect(x: f.midX - s.width / 2, y: f.maxY - s.height,
                          width: s.width, height: s.height)
                .insetBy(dx: -10, dy: -10)
        } else {
            // Open only when the cursor touches the notch itself
            rect = NSRect(x: f.midX - notchSize.width / 2, y: f.maxY - notchSize.height,
                          width: notchSize.width, height: notchSize.height)
                .insetBy(dx: -6, dy: -4)
        }

        let inside = rect.contains(mouse)
        if inside != state.expanded {
            state.expanded = inside
            panel.ignoresMouseEvents = !inside
        }
    }
}

// MARK: - Starts the notch when the app launches

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchController(player: PlayerStore.shared)
    }
}
