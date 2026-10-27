import SwiftUI
import AppKit

// MARK: - Opens the welcome window (the first time the app runs)

@MainActor
final class WelcomeWindowController {
    static let shared = WelcomeWindowController()
    private var window: NSWindow?

    /// Shows the window once. Closing it (with the button or the red dot) counts as seen.
    func showIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "hasSeenWelcome") else { return }
        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
        show()
    }

    /// Also used by Settings > About > "Show welcome again"
    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: WelcomeView(onDone: { [weak self] in
                self?.window?.close()
            }))
            let w = NSWindow(contentViewController: hosting)
            w.title = "Welcome to MusicControl"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - The welcome screen

struct WelcomeView: View {
    let onDone: () -> Void

    @ObservedObject private var player = PlayerStore.shared
    @ObservedObject private var access = FeatureAccess.shared

    private let choices: [Feature] = [.notch, .browserMedia, .shuffleRepeat, .audioControl, .sleepTimer]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 8) {
                stepTitle(1, "Allow access to your music apps")
                Text("macOS asks once for permission to read and control Music and Spotify. Open the apps first, then click Allow and say OK to each message.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Allow access") { player.requestPermissions() }
                    if !player.permissionStatus.isEmpty {
                        Text(player.permissionStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                stepTitle(2, "Find it")
                Text("Look for the MusicControl icon in your menu bar and click it to open the player. While music plays, move your cursor onto the notch for a mini player.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                stepTitle(3, "Choose what you want")
                ForEach(choices) { feature in
                    Toggle(feature.title, isOn: Binding(
                        get: { access.isEnabled(feature) },
                        set: { access.setEnabled(feature, $0) }
                    ))
                }
                LaunchAtLoginToggle()
                Text("You can change all of this later in Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Get started") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 500)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text("Welcome to MusicControl")
                    .font(.title2.bold())
                Text("See what's playing and control it from your menu bar and notch.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stepTitle(_ number: Int, _ title: String) -> some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(title).font(.headline)
        }
    }
}
