import SwiftUI
import AppKit
import Combine

// MARK: - Sizes shared by the window and the view

enum NotchMetrics {
    static let width: CGFloat = 380

    /// The card is as tall as the physical notch plus room for the player.
    /// (MacBook Airs have a taller notch than MacBook Pros, so this is computed, not fixed.)
    static func expandedSize(notchHeight: CGFloat) -> CGSize {
        CGSize(width: width, height: max(207, notchHeight + 177))
    }

    /// The small card that appears briefly when the song changes
    static func peekSize(notchHeight: CGFloat) -> CGSize {
        CGSize(width: 330, height: notchHeight + 50)
    }

    /// Big enough for the tallest card, so the window never clips it
    static let panelSize = CGSize(width: 400, height: 250)
}

final class NotchState: ObservableObject {
    @Published var expanded = false
    @Published var peeking = false
    @Published var page: NotchPage = .music
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

    private var cardSize: CGSize {
        if state.expanded {
            return NotchMetrics.expandedSize(notchHeight: notchHeight)
        }
        if state.peeking {
            return NotchMetrics.peekSize(notchHeight: notchHeight)
        }
        return CGSize(width: notchWidth, height: notchHeight)
    }

    private var bottomRadius: CGFloat {
        if state.expanded { return 26 }
        if state.peeking { return 20 }
        return 10
    }

    var body: some View {
        NotchShape(bottomRadius: bottomRadius)
            .fill(Color.black)
            .frame(width: cardSize.width, height: cardSize.height)
            .overlay(alignment: .top) {
                if state.expanded {
                    expandedContent.transition(.opacity)
                } else if state.peeking {
                    peekContent.transition(.opacity)
                }
            }
            // Draw nothing while collapsed (on every Mac). The black card only
            // appears when the cursor opens it, growing out of the notch area.
            .opacity(state.expanded || state.peeking ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The card is always black, so always use dark-mode text and controls,
            // even when the Mac is in Light Mode.
            .environment(\.colorScheme, .dark)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: state.expanded)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: state.peeking)
            .ignoresSafeArea()
    }

    // MARK: Compact pop-up (shown briefly when the song changes)

    private var peekContent: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: notchHeight)
            HStack(spacing: 10) {
                peekArtwork
                VStack(alignment: .leading, spacing: 1) {
                    Text(player.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(player.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                EqualizerBars(isPlaying: player.isPlaying, color: player.accent, height: 14)
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var peekArtwork: some View {
        if let art = player.artwork {
            Image(nsImage: art)
                .resizable()
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.15))
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: "music.note")
                        .foregroundStyle(Color.white.opacity(0.7))
                )
        }
    }

    // MARK: Full card

    private var expandedContent: some View {
        let pages = availableNotchPages(player: player)
        let current = currentPage(in: pages)

        return ZStack(alignment: .top) {
            VStack(spacing: 8) {
                // Keeps the page content below the physical notch.
                Spacer().frame(height: notchHeight)
                pageContent(current)
                    .id(current)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity)
            }

            // The physical notch occupies the centre, so page icons go in the free
            // pockets on its left and right instead of a row underneath.
            if pages.count > 1 {
                pageIcons(pages, current: current)
            }
        }
        .padding(.bottom, 14)
        .animation(.easeInOut(duration: 0.18), value: current)
    }

    @ViewBuilder
    private func pageContent(_ page: NotchPage) -> some View {
        switch page {
        case .music:
            NotchMusicPage().environmentObject(player)
        case .battery:
            NotchBatteryPage()
        }
    }

    private func currentPage(in pages: [NotchPage]) -> NotchPage {
        if pages.contains(state.page) {
            return state.page
        }
        return pages.first ?? .music
    }

    /// Icons are split between the two sides, so none sit behind the physical notch.
    private func pageIcons(_ pages: [NotchPage], current: NotchPage) -> some View {
        let split = (pages.count + 1) / 2
        let left = Array(pages.prefix(split))
        let right = Array(pages.dropFirst(split))

        return HStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(left) { page in
                    iconButton(page, current: current)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(right) { page in
                    iconButton(page, current: current)
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.top, 4)
    }

    private func iconColor(_ page: NotchPage, current: NotchPage) -> Color {
        if page == current {
            return player.accent
        }
        return Color.white.opacity(0.42)
    }

    private func iconButton(_ page: NotchPage, current: NotchPage) -> some View {
        Button {
            state.page = page
        } label: {
            Image(systemName: page.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(iconColor(page, current: current))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .help(page.title)
        .accessibilityLabel(page.title)
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
    private let host: NSHostingView<AnyView>
    private let state: NotchState
    private let player: PlayerStore
    private var pollTask: Task<Void, Never>?

    private var screenFrame: CGRect
    private var notchSize: CGSize

    private var hoverStart: Date?
    private var leaveStart: Date?
    private var peekEnds: Date?
    private var lastTrackKey = ""

    /// How long the cursor can leave the card before it closes (stops flicker)
    private static let closeDelay: TimeInterval = 0.25
    /// How long the song-change pop-up stays on screen
    private static let peekDuration: TimeInterval = 3.0

    init(player: PlayerStore) {
        let layout = Self.currentLayout()
        let state = NotchState()

        let panel = NotchPanel(contentRect: Self.panelFrame(for: layout.frame),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered,
                               defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let host = NSHostingView(rootView: Self.rootView(state: state, player: player, notch: layout.notch))
        panel.contentView = host
        panel.setFrame(Self.panelFrame(for: layout.frame), display: true)

        self.panel = panel
        self.host = host
        self.state = state
        self.player = player
        self.screenFrame = layout.frame
        self.notchSize = layout.notch

        // Starts hidden. It only appears once there is something to show.
        panel.orderOut(nil)

        // Follow monitors being plugged in, unplugged or changed, and the Mac waking up
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconfigure() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconfigure() }
        }

        // Check the mouse position several times a second
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                self?.updateHover()
            }
        }
    }

    // MARK: - Screen layout

    private static func currentLayout() -> (frame: CGRect, notch: CGSize) {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        // A Mac with no display attached (for example a Mac mini): use a placeholder
        guard let screen else {
            return (CGRect(x: 0, y: 0, width: 1440, height: 900), CGSize(width: 180, height: 28))
        }

        // The real notch size (a fallback size on Macs without a notch)
        var size = CGSize(width: 180, height: 28)
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            size = CGSize(width: screen.frame.width - left.width - right.width,
                          height: screen.safeAreaInsets.top)
        }
        return (screen.frame, size)
    }

    private static func panelFrame(for screen: CGRect) -> NSRect {
        let size = NotchMetrics.panelSize
        return NSRect(x: screen.midX - size.width / 2,
                      y: screen.maxY - size.height,
                      width: size.width,
                      height: size.height)
    }

    private static func rootView(state: NotchState, player: PlayerStore, notch: CGSize) -> AnyView {
        AnyView(
            NotchView(state: state, notchWidth: notch.width, notchHeight: notch.height)
                .environmentObject(player)
        )
    }

    /// Called when the screens change, so the notch window never ends up in the wrong place
    private func reconfigure() {
        let layout = Self.currentLayout()
        screenFrame = layout.frame
        notchSize = layout.notch
        panel.setFrame(Self.panelFrame(for: layout.frame), display: true)
        host.rootView = Self.rootView(state: state, player: player, notch: layout.notch)
        collapse()
    }

    // MARK: - Settings

    private var enabled: Bool {
        FeatureAccess.shared.isActive(.notch)
    }

    /// Off by default: with nothing playing, hovering the notch does nothing.
    private var openWhenIdle: Bool {
        UserDefaults.standard.bool(forKey: "notchOpenWhenIdle")
    }

    /// How long the cursor must rest on the notch before it opens
    private var openDelay: TimeInterval {
        UserDefaults.standard.object(forKey: "notchOpenDelay") as? Double ?? 0.12
    }

    /// Off by default: briefly show the new song when it changes
    private var trackPopupEnabled: Bool {
        UserDefaults.standard.bool(forKey: "notchTrackPopup")
    }

    /// On by default: a small tap on the trackpad when the notch opens
    private var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: "notchHaptics") as? Bool ?? true
    }

    // MARK: - Song changes

    /// True once, at the moment the song changes. The first song seen after launch doesn't count.
    private func trackJustChanged() -> Bool {
        guard player.hasTrack else {
            lastTrackKey = ""
            return false
        }
        let key = "\(player.sourceLabel)|\(player.title)|\(player.artist)"
        let changed = !lastTrackKey.isEmpty && key != lastTrackKey
        lastTrackKey = key
        return changed
    }

    // MARK: - Hover logic

    private func updateHover() {
        let pages = availableNotchPages(player: player)
        let trackChanged = trackJustChanged()

        // Nothing to show (no media, and idle opening is off), or notch switched off:
        // the window is not on screen at all, so hovering over the notch does nothing.
        guard enabled, !pages.isEmpty, player.hasTrack || openWhenIdle else {
            hideCompletely()
            return
        }
        if !panel.isVisible { panel.orderFrontRegardless() }

        let mouse = NSEvent.mouseLocation
        let f = screenFrame

        if state.expanded {
            let size = NotchMetrics.expandedSize(notchHeight: notchSize.height)
            let card = NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                              width: size.width, height: size.height)
                .insetBy(dx: -10, dy: -10)

            if card.contains(mouse) {
                leaveStart = nil
            } else {
                let start = leaveStart ?? Date()
                leaveStart = start
                if Date().timeIntervalSince(start) >= Self.closeDelay {
                    collapse()
                }
            }
        } else {
            // A new song: show the small pop-up for a few seconds (if switched on)
            if trackChanged && trackPopupEnabled && player.hasTrack {
                state.peeking = true
                peekEnds = Date().addingTimeInterval(Self.peekDuration)
            }
            if state.peeking, let end = peekEnds, Date() >= end {
                state.peeking = false
                peekEnds = nil
            }

            // Open only when the cursor rests on the notch itself
            let hotZone = NSRect(x: f.midX - notchSize.width / 2, y: f.maxY - notchSize.height,
                                 width: notchSize.width, height: notchSize.height)
                .insetBy(dx: -6, dy: -4)

            if hotZone.contains(mouse) {
                let start = hoverStart ?? Date()
                hoverStart = start
                if Date().timeIntervalSince(start) >= openDelay {
                    expand(pages)
                }
            } else {
                hoverStart = nil
            }
        }
    }

    private func expand(_ pages: [NotchPage]) {
        state.page = pages.first ?? .music
        state.peeking = false
        peekEnds = nil
        state.expanded = true
        panel.ignoresMouseEvents = false
        hoverStart = nil
        leaveStart = nil

        if hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func collapse() {
        state.expanded = false
        state.peeking = false
        peekEnds = nil
        panel.ignoresMouseEvents = true
        hoverStart = nil
        leaveStart = nil
    }

    private func hideCompletely() {
        if panel.isVisible { panel.orderOut(nil) }
        collapse()
    }
}

// MARK: - Starts the notch when the app launches

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchController(player: PlayerStore.shared)
        UpdateChecker.shared.checkOnLaunchIfNeeded()
        WelcomeWindowController.shared.showIfNeeded()
    }
}
