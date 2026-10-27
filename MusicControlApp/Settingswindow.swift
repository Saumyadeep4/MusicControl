import SwiftUI
import AppKit
import Combine
import ServiceManagement

// MARK: - Which page is showing (so other parts of the app can open a specific page)

@MainActor
final class SettingsNavigation: ObservableObject {
    static let shared = SettingsNavigation()
    @Published var page: SettingsView.Page = .general
}

// MARK: - Opens the settings window (works reliably from a menu bar app)

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(page: SettingsView.Page? = nil) {
        if let page { SettingsNavigation.shared.page = page }

        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView())
            let w = NSWindow(contentViewController: hosting)
            w.title = "MusicControl Settings"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - The window

struct SettingsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case general = "General"
        case music = "Music"
        case library = "Library"
        case notch = "Notch"
        case features = "Features"
        case updates = "Updates"
        case about = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general:   return "gearshape"
            case .music:     return "music.note"
            case .library:   return "clock.arrow.circlepath"
            case .notch:     return "rectangle.topthird.inset.filled"
            case .features:  return "square.grid.2x2"
            case .updates:   return "arrow.down.circle"
            case .about:     return "info.circle"
            }
        }
    }

    @ObservedObject private var nav = SettingsNavigation.shared
    @ObservedObject private var updater = UpdateChecker.shared

    private var pages: [Page] {
        Page.allCases
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 680, height: 480)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(pages) { p in
                sidebarRow(p)
            }
            Spacer()
        }
        .padding(12)
        .frame(width: 180)
    }

    private func rowColor(_ p: Page) -> Color {
        if nav.page == p {
            return Color.accentColor.opacity(0.22)
        }
        return Color.clear
    }

    private func showsUpdateDot(_ p: Page) -> Bool {
        p == .updates && updater.hasUpdate
    }

    private func sidebarRow(_ p: Page) -> some View {
        let highlight = rowColor(p)
        let showDot = showsUpdateDot(p)

        return Button {
            nav.page = p
        } label: {
            HStack {
                Label(p.rawValue, systemImage: p.icon)
                Spacer()
                if showDot {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6).fill(highlight))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch nav.page {
            case .general:   GeneralPage()
            case .music:     MusicPage()
            case .library:   LibraryPage()
            case .notch:     NotchSettingsPage()
            case .features:  FeaturesPage()
            case .updates:   UpdatesPage()
            case .about:     AboutPage()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - General

private struct GeneralPage: View {
    @AppStorage("showArtInMenuBar") private var showArt = true
    @AppStorage("showSongInMenuBar") private var showSong = true
    @AppStorage("menuBarTextStyle") private var textStyle = 0
    @AppStorage("menuBarMaxChars") private var maxChars = 28
    @AppStorage("batteryAlertEnabled") private var batteryAlertEnabled = false
    @AppStorage("batteryAlertThreshold") private var batteryAlertThreshold = 20

    var body: some View {
        Form {
            Section("Startup") {
                LaunchAtLoginToggle()
            }
            Section("Menu bar") {
                Toggle("Show the album cover", isOn: $showArt)
                Toggle("Show the song name", isOn: $showSong)
                Picker("Text shown", selection: $textStyle) {
                    Text("Song - Artist").tag(0)
                    Text("Song only").tag(1)
                    Text("Artist - Song").tag(2)
                }
                .disabled(!showSong)
                HStack {
                    Text("Maximum length")
                    Slider(value: Binding(
                        get: { Double(maxChars) },
                        set: { maxChars = Int($0) }
                    ), in: 12...40, step: 1)
                    Text("\(maxChars)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 28, alignment: .trailing)
                }
                .disabled(!showSong)
            }
            Section("Battery alerts") {
                Toggle("Notify me when battery is low", isOn: $batteryAlertEnabled)
                if batteryAlertEnabled {
                    Picker("Alert at", selection: $batteryAlertThreshold) {
                        Text("10%").tag(10)
                        Text("20%").tag(20)
                        Text("30%").tag(30)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var message = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Open MusicControl when I log in", isOn: Binding(
                get: { enabled },
                set: { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                        message = ""
                    } catch {
                        message = "Couldn't change this: \(error.localizedDescription)"
                    }
                    enabled = SMAppService.mainApp.status == .enabled
                }
            ))
            if SMAppService.mainApp.status == .requiresApproval {
                Text("Approve MusicControl in System Settings > General > Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }
}

// MARK: - Music

private struct MusicPage: View {
    @ObservedObject private var player = PlayerStore.shared
    @ObservedObject private var audio = AudioControlStore.shared
    @AppStorage("appleMusicAudioRuleEnabled") private var audioRuleEnabled = false
    @AppStorage("appleMusicOutputName") private var outputName = ""
    @AppStorage("appleMusicVolume") private var volume = 0.5

    var body: some View {
        Form {
            Section("Apple Music and Spotify") {
                Text("MusicControl needs your permission to read and control these apps. macOS asks once for each.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Allow access to Music & Spotify") { player.requestPermissions() }
                    Button("Open Automation settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                if !player.permissionStatus.isEmpty {
                    Text(player.permissionStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Shuffle and repeat") {
                Text("Shuffle and repeat buttons work with Apple Music and Spotify. Spotify can only switch repeat on or off. Browsers and other apps don't offer these controls, so the buttons stay hidden for them.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Browsers and other apps") {
                Text("Music and video from browsers, Podcasts, TV and other apps is controlled by the \"Browsers & other apps\" switch on the Features page. It needs no permission.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Apply my audio preference when Music starts", isOn: $audioRuleEnabled)
                if audioRuleEnabled {
                    Picker("Output", selection: $outputName) {
                        Text("Keep current output").tag("")
                        ForEach(audio.outputs) { output in
                            Text(output.name).tag(output.name)
                        }
                    }
                    Slider(value: $volume, in: 0...1) { Text("Volume") }
                }
            } header: {
                Text("Apple Music automation")
            } footer: {
                Text("This rule is applied only when Apple Music becomes the active player. It does not alter Spotify or browser media.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Library

private struct LibraryPage: View {
    @ObservedObject private var player = PlayerStore.shared

    var body: some View {
        Form {
            Section("Playback history") {
                if player.history.isEmpty {
                    Text("Tracks you play will appear here. History stays on this Mac.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(player.history.prefix(12)) { track in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).font(.headline)
                            Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Button("Clear history", role: .destructive) { player.clearHistory() }
                }
            }

            Section("Apple Music") {
                Text("Use the heart in the player to favorite the current track. Queue controls are only dependable in Apple Music; Spotify and other media sources show a limitation note.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Notch

private struct NotchSettingsPage: View {
    @AppStorage("notchOpenWhenIdle") private var openWhenIdle = false
    @AppStorage("notchOpenDelay") private var openDelay = 0.12
    @AppStorage("notchTrackPopup") private var trackPopup = false
    @AppStorage("notchHaptics") private var haptics = true

    var body: some View {
        Form {
            Section {
                Toggle("Open the notch even when nothing is playing", isOn: $openWhenIdle)
            } header: {
                Text("When it opens")
            } footer: {
                Text("Off (recommended): the notch does nothing unless something is playing or paused. On: hovering the notch also opens other pages, such as Battery, when no music is loaded.")
            }

            Section {
                Picker("Open speed", selection: $openDelay) {
                    Text("Instant").tag(0.0)
                    Text("Short").tag(0.12)
                    Text("Relaxed").tag(0.35)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Hover")
            } footer: {
                Text("How long the cursor must rest on the notch before it opens. A longer delay avoids opening by accident when you reach for menu bar items.")
            }

            Section {
                Toggle("Show the song briefly when it changes", isOn: $trackPopup)
                Toggle("Haptic tap when the notch opens", isOn: $haptics)
            } header: {
                Text("Extras")
            } footer: {
                Text("The song pop-up appears under the notch for a few seconds when a new song starts. The haptic tap is felt on a MacBook trackpad.")
            }

            Section("Pages") {
                Text("Music appears while something is loaded. Battery and other pages are switched on or off on the Features page. When more than one page is available, small icons beside the notch let you switch.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Features

private struct FeaturesPage: View {
    @ObservedObject private var access = FeatureAccess.shared

    var body: some View {
        Form {
            Section {
                ForEach(Feature.allCases) { feature in
                    row(feature)
                }
            } footer: {
                Text("Switch features on or off.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func row(_ feature: Feature) -> some View {
        HStack(spacing: 12) {
            Image(systemName: feature.systemImage)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(.headline)
                Text(feature.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { access.isEnabled(feature) },
                set: { access.setEnabled(feature, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Updates

private struct UpdatesPage: View {
    @ObservedObject private var updater = UpdateChecker.shared
    @AppStorage("autoCheckUpdates") private var autoCheck = true

    var body: some View {
        Form {
            Section("Version") {
                LabeledContent("Installed", value: updater.versionDescription)

                status

                HStack {
                    Button("Check for updates") { Task { await updater.check() } }
                        .disabled(updater.isChecking)
                    if updater.isChecking {
                        ProgressView().controlSize(.small)
                    }
                }
            }

            Section {
                Toggle("Check for updates automatically (once a day)", isOn: $autoCheck)
            } footer: {
                Text("Checking contacts github.com to read the latest release. No personal information is sent.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var status: some View {
        switch updater.state {
        case .idle:
            if let date = updater.lastChecked {
                Text("Last checked \(date.formatted(.relative(presentation: .named))).")
                    .foregroundStyle(.secondary)
            } else {
                Text("Not checked yet.").foregroundStyle(.secondary)
            }

        case .checking:
            Text("Checking…").foregroundStyle(.secondary)

        case .upToDate:
            Label("You're up to date.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .available(let version, let url, let notes):
            VStack(alignment: .leading, spacing: 8) {
                Label("Version \(version) is available.", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.green)
                if !notes.isEmpty {
                    ScrollView {
                        Text(notes)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                }
                Button("Download version \(version)") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderedProminent)
            }

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - About

private struct AboutPage: View {
    @ObservedObject private var updater = UpdateChecker.shared
    @State private var copied = false

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "MusicControl"
    }

    private var repoURL: URL {
        URL(string: "https://github.com/\(UpdateChecker.owner)/\(UpdateChecker.repo)")!
    }

    /// Version, Mac and settings details for bug reports. It contains no song titles or personal data.
    private func diagnosticsText() -> String {
        let access = FeatureAccess.shared
        let player = PlayerStore.shared
        let hasNotch = NSScreen.screens.contains { $0.safeAreaInsets.top > 0 }

        var lines: [String] = []
        lines.append("MusicControl \(updater.versionDescription)")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Mac model: \(hardwareModel())")
        lines.append("Notch on a connected screen: \(hasNotch ? "yes" : "no")")
        lines.append("Playback source: \(player.hasTrack ? player.sourceLabel : "nothing playing")")
        if !player.permissionStatus.isEmpty {
            lines.append("Permissions:")
            lines.append(player.permissionStatus)
        }
        lines.append("Features:")
        for feature in Feature.allCases {
            lines.append("  \(feature.title): \(access.isActive(feature) ? "on" : "off")")
        }
        return lines.joined(separator: "\n")
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsText(), forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)

            Text(appName).font(.title2.bold())
            Text("Version \(updater.versionDescription)").foregroundStyle(.secondary)

            HStack(spacing: 18) {
                Link("Downloads & support", destination: repoURL)
                Link("Report a problem", destination: repoURL.appendingPathComponent("issues"))
            }
            .padding(.top, 4)

            HStack(spacing: 12) {
                Button(copied ? "Copied" : "Copy diagnostics") { copyDiagnostics() }
                Button("Show welcome again") { WelcomeWindowController.shared.show() }
            }
            .padding(.top, 2)

            Divider().padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 6) {
                Text("Credits").font(.headline)
                Text("Support for browsers and other apps uses MediaRemoteAdapter, copyright © 2025 Jonas van den Berg and contributors (BSD 3-Clause License), with a Swift package by ejbills.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("github.com/ungive/mediaremote-adapter",
                     destination: URL(string: "https://github.com/ungive/mediaremote-adapter")!)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(24)
    }
}

// MARK: - Helpers

/// For example "MacBookPro18,3". Useful when someone reports a bug.
private func hardwareModel() -> String {
    var size = 0
    sysctlbyname("hw.model", nil, &size, nil, 0)
    guard size > 0 else { return "unknown" }
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname("hw.model", &buffer, &size, nil, 0)
    return String(cString: buffer)
}
