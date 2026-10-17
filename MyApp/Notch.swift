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

    /// Big enough for the tallest card, so the window never clips it
    static let panelSize = CGSize(width: 400, height: 250)
}

final class NotchState: ObservableObject {
    @Published var expanded = false
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
        return CGSize(width: notchWidth, height: notchHeight)
    }

    var body: some View {
        NotchShape(bottomRadius: state.expanded ? 26 : 10)
            .fill(Color.black)
            .frame(width: cardSize.width, height: cardSize.height)
            .overlay(alignment: .top) {
                if state.expanded {
                    expandedContent.transition(.opacity)
                }
            }
            // Draw nothing while collapsed (on every Mac). The black card only
            // appears when the cursor opens it, growing out of the notch area.
            .opacity(state.expanded ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The card is always black, so always use dark-mode text and controls,
            // even when the Mac is in Light Mode.
            .environment(\.colorScheme, .dark)
            .animation(.spring(response: 0.38, dampingFraction: 0.78), value: state.expanded)
            .ignoresSafeArea()
    }

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

    private var hoverStart: Date?
    private var leaveStart: Date?

    /// How long the cursor can leave the card before it closes (stops flicker)
    private static let closeDelay: TimeInterval = 0.25

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
                      notchHeight: size.height)
                .environmentObject(player)
        )
        panel.contentView = host
        panel.setFrame(frame, display: true)

        self.screen = screen
        self.notchSize = size
        self.state = state
        self.panel = panel
        self.player = player

        // Starts hidden. It only appears once there is something to show.
        panel.orderOut(nil)

        // Check the mouse position several times a second
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                self?.updateHover()
            }
        }
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

    // MARK: - Hover logic

    private func updateHover() {
        let pages = availableNotchPages(player: player)

        // Nothing to show (no media, and idle opening is off), or notch switched off:
        // the window is not on screen at all, so hovering over the notch does nothing.
        guard enabled, !pages.isEmpty, player.hasTrack || openWhenIdle else {
            hideCompletely()
            return
        }
        if !panel.isVisible { panel.orderFrontRegardless() }

        let mouse = NSEvent.mouseLocation
        let f = screen.frame

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
        state.expanded = true
        panel.ignoresMouseEvents = false
        hoverStart = nil
        leaveStart = nil
    }

    private func collapse() {
        state.expanded = false
        panel.ignoresMouseEvents = true
        hoverStart = nil
        leaveStart = nil
    }

    private func hideCompletely() {
        if panel.isVisible { panel.orderOut(nil) }
        state.expanded = false
        panel.ignoresMouseEvents = true
        hoverStart = nil
        leaveStart = nil
    }
}

// MARK: - Starts the notch when the app launches

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var notch: NotchController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchController(player: PlayerStore.shared)
        UpdateChecker.shared.checkOnLaunchIfNeeded()
    }
}
