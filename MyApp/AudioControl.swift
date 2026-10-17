import Combine
import CoreAudio
import SwiftUI

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

/// Controls the system's current audio output. This is deliberately separate from
/// PlayerStore: it works with Apple Music, Spotify, browsers, and any other player.
/// It only reads and sets output devices, so it never triggers a microphone prompt.
@MainActor
final class AudioControlStore: ObservableObject {
    static let shared = AudioControlStore()

    @Published private(set) var volume: Double = 0.5
    @Published private(set) var isMuted = false
    /// False for outputs that have no software volume (some HDMI/DisplayPort monitors, some USB DACs)
    @Published private(set) var canSetVolume = false
    @Published private(set) var outputName = "Mac audio"
    @Published private(set) var outputID: AudioDeviceID = 0
    @Published private(set) var outputs: [AudioOutputDevice] = []
    private var outputTransportType: UInt32 = 0

    /// An output-specific symbol makes the picker easier to scan than a generic
    /// AirPlay icon. Device names are the most portable signal across macOS outputs.
    var outputIcon: String {
        let name = outputName.lowercased()
        if name.contains("airpods max") || name.contains("airpodsmax") {
            return "airpodsmax"
        }
        if name.contains("airpods pro") || name.contains("airpodspro") {
            return "airpodspro"
        }
        if name.contains("airpod") || name.contains("headphone") || name.contains("earbuds") ||
            name.contains("headset") || name.contains("bluetooth") {
            return "airpods"
        }
        if name.contains("hdmi") || name.contains("displayport") || name.contains("display port") {
            return "tv"
        }
        if name.contains("macbook") || name.contains("built-in") || name.contains("internal") {
            return "laptopcomputer"
        }
        if name.contains("usb") {
            return "cable.connector"
        }
        if name.contains("speaker") || name.contains("homepod") {
            return "hifispeaker.fill"
        }
        if outputTransportType == kAudioDeviceTransportTypeBluetooth ||
            outputTransportType == kAudioDeviceTransportTypeBluetoothLE {
            return "airpods"
        }
        return "waveform"
    }

    private var volumeBeforeMute: Double = 0.5
    private var pollTask: Task<Void, Never>?

    private init() {
        refresh()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                self?.refresh()
            }
        }
    }

    // MARK: - Reading

    func refresh() {
        let device = defaultOutputDevice()
        guard device != AudioDeviceID(kAudioObjectUnknown) else { return }

        outputID = device
        outputName = deviceName(device) ?? "Mac audio"
        outputTransportType = transportType(device)

        let volumeElements = controlElements(device, kAudioDevicePropertyVolumeScalar)
        canSetVolume = !volumeElements.isEmpty
        if let current = readVolume(device, elements: volumeElements) {
            volume = current
        }

        let muteElements = controlElements(device, kAudioDevicePropertyMute)
        if let muted = readMute(device, elements: muteElements) {
            isMuted = muted
        } else {
            isMuted = canSetVolume && volume < 0.01
        }

        let list = outputDevices()
        if list != outputs {
            outputs = list
        }
    }

    // MARK: - Changing

    func setVolume(_ value: Double) {
        let device = defaultOutputDevice()
        let elements = controlElements(device, kAudioDevicePropertyVolumeScalar)
        guard !elements.isEmpty else { return }

        let scalar = Float32(min(max(value, 0), 1))
        for element in elements {
            var newValue = scalar
            var addr = address(kAudioDevicePropertyVolumeScalar, element: element)
            AudioObjectSetPropertyData(device, &addr, 0, nil,
                                       UInt32(MemoryLayout<Float32>.size), &newValue)
        }
        volume = Double(scalar)

        // Moving the slider unmutes, like the system volume does
        let muteElements = controlElements(device, kAudioDevicePropertyMute)
        if isMuted && scalar > 0 && !muteElements.isEmpty {
            writeMute(false, on: device, elements: muteElements)
            isMuted = false
        }
    }

    func toggleMute() {
        let device = defaultOutputDevice()
        let muteElements = controlElements(device, kAudioDevicePropertyMute)

        if !muteElements.isEmpty {
            let newValue = !isMuted
            writeMute(newValue, on: device, elements: muteElements)
            isMuted = newValue
        } else if canSetVolume {
            // This output has no mute control, so mute by moving the volume to zero
            if volume > 0.01 {
                volumeBeforeMute = volume
                setVolume(0)
                isMuted = true
            } else {
                setVolume(volumeBeforeMute)
                isMuted = false
            }
        }
    }

    func selectOutput(_ device: AudioOutputDevice) {
        var id = device.id
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id
        )
        if status == noErr { refresh() }
    }

    // MARK: - Devices

    private func defaultOutputDevice() -> AudioDeviceID {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private func outputDevices() -> [AudioOutputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else {
            return []
        }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return []
        }

        var result: [AudioOutputDevice] = []
        for id in ids where hasOutputStreams(id) {
            result.append(AudioOutputDevice(id: id, name: deviceName(id) ?? "Audio device"))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr && size > 0
    }

    private func deviceName(_ device: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &name)
        guard status == noErr, let name else { return nil }
        // CoreAudio gives us a string we own, so take it as retained to avoid a leak
        return name.takeRetainedValue() as String
    }

    private func transportType(_ device: AudioDeviceID) -> UInt32 {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    // MARK: - Volume and mute plumbing

    private func address(_ selector: AudioObjectPropertySelector,
                         element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private func isSettable(_ device: AudioDeviceID,
                            _ selector: AudioObjectPropertySelector,
                            element: AudioObjectPropertyElement) -> Bool {
        var addr = address(selector, element: element)
        guard AudioObjectHasProperty(device, &addr) else { return false }
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &addr, &settable) == noErr else { return false }
        return settable.boolValue
    }

    /// Which elements control this property: the main one, or else the left and right channels.
    /// Empty means this output can't be controlled in software.
    private func controlElements(_ device: AudioDeviceID,
                                 _ selector: AudioObjectPropertySelector) -> [AudioObjectPropertyElement] {
        if isSettable(device, selector, element: kAudioObjectPropertyElementMain) {
            return [kAudioObjectPropertyElementMain]
        }
        let channels: [AudioObjectPropertyElement] = [1, 2]
        return channels.filter { isSettable(device, selector, element: $0) }
    }

    private func readVolume(_ device: AudioDeviceID, elements: [AudioObjectPropertyElement]) -> Double? {
        var values: [Double] = []
        for element in elements {
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            var addr = address(kAudioDevicePropertyVolumeScalar, element: element)
            if AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr {
                values.append(Double(value))
            }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func readMute(_ device: AudioDeviceID, elements: [AudioObjectPropertyElement]) -> Bool? {
        guard let element = elements.first else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = address(kAudioDevicePropertyMute, element: element)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private func writeMute(_ muted: Bool, on device: AudioDeviceID, elements: [AudioObjectPropertyElement]) {
        for element in elements {
            var value: UInt32 = muted ? 1 : 0
            var addr = address(kAudioDevicePropertyMute, element: element)
            AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        }
    }
}

// MARK: - The volume row (mute, slider, output picker)

struct AudioControlBar: View {
    @ObservedObject private var audio = AudioControlStore.shared

    private var speakerSymbol: String {
        if audio.isMuted || audio.volume < 0.01 { return "speaker.slash.fill" }
        if audio.volume < 0.34 { return "speaker.wave.1.fill" }
        if audio.volume < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {
        HStack(spacing: 10) {
            Button { audio.toggleMute() } label: {
                Image(systemName: speakerSymbol)
                    .frame(width: 20)
            }
            .buttonStyle(.plain)
            .help(audio.isMuted ? "Unmute" : "Mute")

            Slider(value: Binding(
                get: { audio.volume },
                set: { audio.setVolume($0) }
            ), in: 0...1)
            .tint(.white)
            .disabled(!audio.canSetVolume)
            .help(audio.canSetVolume ? "Volume" : "This output has no volume control. Use the device itself.")

            Menu {
                ForEach(audio.outputs) { output in
                    Button {
                        audio.selectOutput(output)
                    } label: {
                        if output.id == audio.outputID {
                            Label(output.name, systemImage: "checkmark")
                        } else {
                            Text(output.name)
                        }
                    }
                }
            } label: {
                Image(systemName: audio.outputIcon)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 24)
            .help("Output: \(audio.outputName)")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.78))
        .padding(.horizontal, 3)
        .onAppear { audio.refresh() }
    }
}
