import SwiftUI

// MARK: - Scrolling text

private struct MarqueeWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Text that stays still when it fits, and scrolls slowly sideways when it is too long.
/// (Long song titles used to be cut off with "...".)
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color
    var alignment: Alignment = .leading

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var textWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    /// Scroll speed in points per second
    private let speed: CGFloat = 28

    var body: some View {
        // An invisible copy of the text reserves the correct height for one line
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(0)
            .frame(maxWidth: .infinity, alignment: alignment)
            .overlay {
                if reduceMotion {
                    // People who turn on Reduce Motion get plain, truncated text
                    Text(text)
                        .font(font)
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: alignment)
                } else {
                    GeometryReader { geo in
                        scrollingText(containerWidth: geo.size.width)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    private func scrollingText(containerWidth: CGFloat) -> some View {
        let overflow = textWidth - containerWidth
        let scrolls = overflow > 1
        let taskID = "\(text)|\(Int(containerWidth))|\(Int(textWidth))"

        return Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize()
            .background(
                GeometryReader { textGeo in
                    Color.clear.preference(key: MarqueeWidthKey.self, value: textGeo.size.width)
                }
            )
            .offset(x: scrolls ? offset : 0)
            .frame(width: containerWidth, alignment: scrolls ? .leading : alignment)
            .clipped()
            .onPreferenceChange(MarqueeWidthKey.self) { textWidth = $0 }
            .task(id: taskID) {
                await scroll(overflow: overflow)
            }
    }

    @MainActor
    private func scroll(overflow: CGFloat) async {
        offset = 0
        guard overflow > 1 else { return }

        let distance = overflow + 14
        let duration = Double(distance / speed)

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1.6))
            if Task.isCancelled { break }
            withAnimation(.linear(duration: duration)) { offset = -distance }

            try? await Task.sleep(for: .seconds(duration + 1.2))
            if Task.isCancelled { break }
            withAnimation(.easeInOut(duration: 0.4)) { offset = 0 }

            try? await Task.sleep(for: .seconds(0.4))
        }
    }
}

// MARK: - Equaliser bars

/// Small bouncing bars shown while music plays. They are decorative: they don't listen to the audio.
struct EqualizerBars: View {
    let isPlaying: Bool
    let color: Color
    var height: CGFloat = 16

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let barCount = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !isPlaying || reduceMotion)) { context in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: barHeight(index, at: context.date))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(_ index: Int, at date: Date) -> CGFloat {
        let low = height * 0.25
        guard isPlaying else { return low }
        if reduceMotion {
            let still: [CGFloat] = [0.45, 0.8, 0.6, 0.35]
            return height * still[index % still.count]
        }

        let time = date.timeIntervalSinceReferenceDate
        let speed = 3.0 + Double(index) * 1.3
        let wave = (sin(time * speed + Double(index) * 1.7) + 1) / 2
        return low + CGFloat(wave) * (height - low)
    }
}
