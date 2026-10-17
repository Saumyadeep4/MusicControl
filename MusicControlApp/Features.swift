import SwiftUI
import Combine

// MARK: - Every feature that can be switched on/off (and made Pro)

enum Feature: String, CaseIterable, Identifiable {
    case notch
    case shuffleRepeat
    case audioControl
    case browserMedia
    case battery
    // Add new features here as they get built (playlists, calendar, mirror, shelf...).

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch:         return "Notch player"
        case .shuffleRepeat: return "Shuffle & repeat"
        case .audioControl:  return "Volume & output"
        case .browserMedia:  return "Browsers & other apps"
        case .battery:       return "Battery"
        }
    }

    var detail: String {
        switch self {
        case .notch:
            return "Hover over the notch to open a mini player. It only appears while something is loaded."
        case .shuffleRepeat:
            return "Shuffle and repeat buttons next to the playback controls, for Apple Music and Spotify."
        case .audioControl:
            return "A volume slider, mute button and output picker (speakers, headphones, AirPlay) under the player."
        case .browserMedia:
            return "Show music and video from browsers, Podcasts, TV, QuickTime and other apps."
        case .battery:
            return "A compact charge, power and time-remaining page in the notch and the menu bar player."
        }
    }

    var systemImage: String {
        switch self {
        case .notch:         return "rectangle.topthird.inset.filled"
        case .shuffleRepeat: return "shuffle"
        case .audioControl:  return "speaker.wave.2"
        case .browserMedia:  return "globe"
        case .battery:       return "battery.100"
        }
    }

    /// THE PRO SWITCH. One line per feature.
    /// true  (1) = behind the paywall
    /// false (0) = free for everyone
    var defaultIsPro: Bool {
        switch self {
        case .notch:         return true
        case .shuffleRepeat: return true
        case .audioControl:  return true
        case .browserMedia:  return true
        case .battery:       return true
        }
    }

    /// Is the feature switched on the first time the app runs?
    var defaultEnabled: Bool { true }

    /// UserDefaults key for the user's own on/off switch.
    /// (Keep these names stable, so people's choices survive updates.)
    var enabledKey: String {
        switch self {
        case .notch:         return "showNotch"
        case .shuffleRepeat: return "showShuffleRepeat"
        case .audioControl:  return "showAudioControls"
        case .browserMedia:  return "showSystemMedia"
        case .battery:       return "showBattery"
        }
    }

    fileprivate var proKey: String { "pro.\(rawValue)" }
}

// MARK: - Decides what is available

/// Use `FeatureAccess.shared.isActive(.something)` anywhere a feature decides whether to run.
/// It is true only when the user has switched the feature on AND it is not locked behind Pro.
@MainActor
final class FeatureAccess: ObservableObject {
    static let shared = FeatureAccess()

    private let defaults = UserDefaults.standard

    /// Placeholder for the future licence check. The current public build is
    /// the free edition, so it must always start locked until real licensing
    /// is implemented. This deliberately ignores any old developer preference
    /// left behind by an earlier test build.
    @Published var proUnlocked: Bool {
        didSet { defaults.set(proUnlocked, forKey: "license.proUnlocked") }
    }

    init() {
        proUnlocked = false
    }

    // The user's on/off switch
    func isEnabled(_ feature: Feature) -> Bool {
        defaults.object(forKey: feature.enabledKey) as? Bool ?? feature.defaultEnabled
    }

    func setEnabled(_ feature: Feature, _ value: Bool) {
        guard !isLocked(feature) else { return }
        defaults.set(value, forKey: feature.enabledKey)
        objectWillChange.send()
    }

    // The public build uses the feature table as the source of truth. Older
    // developer builds could persist `pro.*` overrides, but those must not
    // silently turn a paid feature into a free one after an update.
    func isPro(_ feature: Feature) -> Bool {
        feature.defaultIsPro
    }

    func setPro(_ feature: Feature, _ value: Bool) {
        defaults.set(value, forKey: feature.proKey)
        objectWillChange.send()
    }

    func resetProSwitches() {
        for feature in Feature.allCases { defaults.removeObject(forKey: feature.proKey) }
        objectWillChange.send()
    }

    /// Pro feature and Pro isn't unlocked
    func isLocked(_ feature: Feature) -> Bool {
        isPro(feature) && !proUnlocked
    }

    /// Should this feature actually run right now?
    func isActive(_ feature: Feature) -> Bool {
        isEnabled(feature) && !isLocked(feature)
    }

    /// The Developer page is always there in Xcode builds. In exported builds it stays hidden
    /// unless you run: defaults write <bundle id> developerTools -bool true
    static var developerToolsVisible: Bool {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "developerTools")
        #endif
    }
}
