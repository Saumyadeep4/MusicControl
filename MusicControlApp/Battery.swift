import SwiftUI
import Combine
import IOKit.ps
import UserNotifications

/// Reads the Mac's battery (level, charging, time left). Needs no permission.
/// On a Mac without a battery (for example a Mac mini) `hasBattery` stays false.
@MainActor
final class BatteryStore: ObservableObject {
    static let shared = BatteryStore()

    @Published var hasBattery = false
    @Published var percent = 0
    @Published var isCharging = false
    @Published var onACPower = false
    @Published var isFullyCharged = false
    @Published var minutesRemaining: Int?
    @Published var lowPowerMode = false

    private var pollTask: Task<Void, Never>?
    private var didAlertAtCurrentLowLevel = false

    private init() {
        refresh()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                self?.refresh()
            }
        }
    }

    deinit { pollTask?.cancel() }

    // MARK: - Reading the battery

    func refresh() {
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [AnyObject] else {
            hasBattery = false
            return
        }

        for source in list {
            guard let details = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = details[kIOPSTypeKey] as? String
            guard type == kIOPSInternalBatteryType else { continue }

            let current = details[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = details[kIOPSMaxCapacityKey] as? Int ?? 100
            var level = 0
            if maximum > 0 {
                let ratio = Double(current) / Double(maximum)
                level = Int((ratio * 100).rounded())
            }
            percent = min(100, max(0, level))

            isCharging = details[kIOPSIsChargingKey] as? Bool ?? false
            isFullyCharged = details[kIOPSIsChargedKey] as? Bool ?? false
            let powerState = details[kIOPSPowerSourceStateKey] as? String
            onACPower = powerState == kIOPSACPowerValue
            sendLowBatteryAlertIfNeeded()

            var minutes: Int?
            if isCharging {
                minutes = details[kIOPSTimeToFullChargeKey] as? Int
            } else {
                minutes = details[kIOPSTimeToEmptyKey] as? Int
            }
            if let value = minutes, value > 0 {
                minutesRemaining = value
            } else {
                minutesRemaining = nil
            }

            hasBattery = true
            return
        }

        hasBattery = false
    }

    private func sendLowBatteryAlertIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "batteryAlertEnabled") else { return }
        let threshold = defaults.object(forKey: "batteryAlertThreshold") as? Int ?? 20
        guard percent <= threshold, !isCharging else {
            didAlertAtCurrentLowLevel = false
            return
        }
        guard !didAlertAtCurrentLowLevel else { return }
        didAlertAtCurrentLowLevel = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Battery at \(self.percent)%"
            content.body = "Your Mac is running on battery."
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "low-battery", content: content, trigger: nil))
        }
    }

    // MARK: - Text and colours for the views

    var statusText: String {
        if isFullyCharged && onACPower {
            return "Fully charged"
        }
        if isCharging {
            if let minutes = minutesRemaining {
                return "Charging · \(Self.format(minutes)) to full"
            }
            return "Charging"
        }
        if onACPower {
            return "Plugged in · not charging"
        }
        if let minutes = minutesRemaining {
            return "On battery · \(Self.format(minutes)) left"
        }
        return "On battery"
    }

    var symbolName: String {
        if isCharging {
            return "battery.100.bolt"
        }
        if percent > 87 { return "battery.100" }
        if percent > 62 { return "battery.75" }
        if percent > 37 { return "battery.50" }
        if percent > 12 { return "battery.25" }
        return "battery.0"
    }

    var tint: Color {
        if isCharging || isFullyCharged {
            return Color.green
        }
        if percent <= 20 {
            return Color.red
        }
        return Color.white
    }

    private static func format(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours > 0 {
            return "\(hours) h \(rest) min"
        }
        return "\(rest) min"
    }
}
