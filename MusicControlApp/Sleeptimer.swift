import SwiftUI
import Combine

/// Stops the music after a set time, or when the current song ends.
@MainActor
final class SleepTimerStore: ObservableObject {
    static let shared = SleepTimerStore()

    @Published private(set) var endDate: Date?
    @Published private(set) var remaining: TimeInterval = 0

    private var tickTask: Task<Void, Never>?

    var isActive: Bool { endDate != nil }

    private init() {}

    func start(minutes: Int) {
        begin(after: TimeInterval(minutes * 60))
    }

    /// Uses the time left in the song that is playing now
    func startAtEndOfSong() {
        let player = PlayerStore.shared
        let timeLeft = max(player.duration - player.position, 1)
        begin(after: timeLeft)
    }

    func cancel() {
        tickTask?.cancel()
        tickTask = nil
        endDate = nil
        remaining = 0
    }

    private func begin(after seconds: TimeInterval) {
        tickTask?.cancel()

        let target = Date().addingTimeInterval(seconds)
        endDate = target
        remaining = seconds

        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let deadline = self.endDate else { return }

                let left = deadline.timeIntervalSinceNow
                if left <= 0 {
                    self.finish()
                    return
                }
                self.remaining = left
            }
        }
    }

    private func finish() {
        cancel()
        let player = PlayerStore.shared
        if player.isPlaying {
            player.playPause()
        }
    }

    var remainingText: String {
        let total = Int(remaining.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Small moon button with a menu of timer options (shown in the player footer)
struct SleepTimerButton: View {
    @ObservedObject private var timer = SleepTimerStore.shared

    var body: some View {
        Menu {
            if timer.isActive {
                Text("Music stops in \(timer.remainingText)")
                Button("Cancel timer") { timer.cancel() }
                Divider()
            }
            Button("In 15 minutes") { timer.start(minutes: 15) }
            Button("In 30 minutes") { timer.start(minutes: 30) }
            Button("In 45 minutes") { timer.start(minutes: 45) }
            Button("In 1 hour") { timer.start(minutes: 60) }
            Button("When this song ends") { timer.startAtEndOfSong() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: timer.isActive ? "moon.zzz.fill" : "moon.zzz")
                if timer.isActive {
                    Text(timer.remainingText)
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                }
            }
            .foregroundStyle(Color.white.opacity(timer.isActive ? 0.85 : 0.5))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sleep timer")
        .accessibilityLabel("Sleep timer")
    }
}
