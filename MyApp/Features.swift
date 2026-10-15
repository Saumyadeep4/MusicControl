import SwiftUI
import Combine

// MARK: - Every feature that can be switched on/off (and made Pro)

enum Feature: String, CaseIterable, Identifiable {
    case notch
    case battery
    case browserMedia
    // Add music-related options here as they get built.

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch:        return "Notch player"
        case .battery:      return "Battery"
        case .browserMedia: return "Browsers & other apps"
        }
    }

    var detail: String {
        switch self {
        case .notch:
            return "Hover over the notch to open a mini player. It only appears while something is loaded."
        case .battery:
            return "Show a compact charge, power and time-remaining glance in the notch and menu-bar popover."
        case .browserMedia:
            return "Show music and video from browsers, Podcasts, TV, QuickTime and other apps."
        }
    }

    var systemImage: String {
        switch self {
        case .notch:        return "rectangle.topthird.inset.filled"
        case .battery:      return "battery.100"
        case .browserMedia: return "globe"
        }
    }

    /// THE PRO SWITCH. One line per feature.
    /// true  (1) = behind the paywall
    /// false (0) = free for everyone
    var defaultIsPro: Bool {
        switch self {
        case .notch:        return false
        case .battery:      return false
        case .browserMedia: return false
        }
    }

    /// Is the feature switched on the first time the app runs?
    var defaultEnabled: Bool { true }

    /// UserDefaults key for the user's own on/off switch.
    /// (These two keep the names the app already used.)
    var enabledKey: String {
        switch self {
        case .notch:        return "showNotch"
        case .battery:      return "showBattery"
        case .browserMedia: return "showSystemMedia"
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

    /// PLACEHOLDER for the real licence check. For now it is just a switch
    /// (Settings > Developer > "Simulate Pro unlocked"). Replace with real licensing later.
    @Published var proUnlocked: Bool {
        didSet { defaults.set(proUnlocked, forKey: "license.proUnlocked") }
    }

    init() {
        proUnlocked = UserDefaults.standard.bool(forKey: "license.proUnlocked")
    }

    // The user's on/off switch
    func isEnabled(_ feature: Feature) -> Bool {
        defaults.object(forKey: feature.enabledKey) as? Bool ?? feature.defaultEnabled
    }

    func setEnabled(_ feature: Feature, _ value: Bool) {
        defaults.set(value, forKey: feature.enabledKey)
        objectWillChange.send()
    }

    // The Pro switch (1 = behind the paywall). Starts from the table in `Feature.defaultIsPro`,
    // and can be flipped at run time from Settings > Developer.
    func isPro(_ feature: Feature) -> Bool {
        defaults.object(forKey: feature.proKey) as? Bool ?? feature.defaultIsPro
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
