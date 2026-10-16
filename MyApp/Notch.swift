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

    @State private var selectedPage: NotchPage = .music

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
        let pages = availableNotchPages(player: player)
        return ZStack(alignment: .top) {
            VStack(spacing: 8) {
                // Keeps the page content below the physical notch.
                Spacer().frame(height: notchHeight)
                pageContent(currentPage(in: pages))
                    .frame(maxWidth: .infinity)
            }

            // The physical notch occupies the centre. Put the page controls in
            // the unused left/right pockets instead of adding another row below it.
            if pages.count > 1 {
                HStack(spacing: 0) {
                    pocketButton(pages[0], pages: pages)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        ForEach(pages.dropFirst()) { page in
                            pocketButton(page, pages: pages)
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 4)
            }
        }
        .padding(.bottom, 14)
        .onChange(of: pages) { _, newPages in
            if !newPages.contains(selectedPage) { selectedPage = newPages.first ?? .music }
        }
    }

    private func pocketButton(_ page: NotchPage, pages: [NotchPage]) -> some View {
        Button {
            selectedPage = page
        } label: {
            Image(systemName: page.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(page == currentPage(in: pages)
                                 ? player.accent
                                 : Color.white.opacity(0.42))
                .frame(width: 28, height: 24)
        }
        .buttonStyle(.plain)
        .help(page.title)
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
        pages.contains(selectedPage) ? selectedPage : (pages.first ?? .music)
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
        FeatureAccess.shared.isActive(.notch)
    }

    private func updateHover() {
        // No media loaded (or notch turned off): the notch window is not on screen at all,
        // so hovering over the notch does nothing.
        guard enabled, !availableNotchPages(player: player).isEmpty else {
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
        UpdateChecker.shared.checkOnLaunchIfNeeded()
    }
}
