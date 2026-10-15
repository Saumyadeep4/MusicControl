import Combine
import CoreAudio
import SwiftUI

struct AudioOutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

/// Controls the system's current audio output. This is deliberately separate from
/// PlayerStore: it works with Apple Music, Spotify, browsers, and any other player.
@MainActor
final class AudioControlStore: ObservableObject {
    static let shared = AudioControlStore()

    @Published private(set) var volume: Double = 0.5
    @Published private(set) var isMuted = false
    @Published private(set) var outputName = "Mac audio"
    @Published private(set) var outputs: [AudioOutputDevice] = []

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

    func refresh() {
        let device = defaultOutputDevice()
        outputName = deviceName(device) ?? "Mac audio"
        volume = readScalar(kAudioDevicePropertyVolumeScalar, on: device) ?? volume
        isMuted = (readUInt32(kAudioDevicePropertyMute, on: device) ?? 0) != 0
        outputs = outputDevices()
    }

    func setVolume(_ value: Double) {
        let scalar = Float32(min(max(value, 0), 1))
        writeScalar(kAudioDevicePropertyVolumeScalar, value: scalar, on: defaultOutputDevice())
        volume = Double(scalar)
    }

    func toggleMute() {
        let device = defaultOutputDevice()
        let newValue: UInt32 = isMuted ? 0 : 1
        writeUInt32(kAudioDevicePropertyMute, value: newValue, on: device)
        isMuted = newValue != 0
    }

    func selectOutput(_ device: AudioOutputDevice) {
        var id = device.id
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &id
        )
        if status == noErr { refresh() }
    }

    private func defaultOutputDevice() -> AudioDeviceID {
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    private func outputDevices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else {
            return []
        }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids.compactMap { id in
            hasOutputStreams(id) ? AudioOutputDevice(id: id, name: deviceName(id) ?? "Audio device") : nil
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private func deviceName(_ device: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else { return nil }
        return name?.takeUnretainedValue() as String?
    }

    private func readScalar(_ selector: AudioObjectPropertySelector, on device: AudioDeviceID) -> Double? {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = outputAddress(selector)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    private func writeScalar(_ selector: AudioObjectPropertySelector, value: Float32, on device: AudioDeviceID) {
        var value = value
        var address = outputAddress(selector)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    private func readUInt32(_ selector: AudioObjectPropertySelector, on device: AudioDeviceID) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = outputAddress(selector)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func writeUInt32(_ selector: AudioObjectPropertySelector, value: UInt32, on device: AudioDeviceID) {
        var value = value
        var address = outputAddress(selector)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    private func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

struct AudioControlBar: View {
    @ObservedObject private var audio = AudioControlStore.shared

    var body: some View {
        HStack(spacing: 10) {
            Button { audio.toggleMute() } label: {
                Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .frame(width: 18)
            }
            .help(audio.isMuted ? "Unmute" : "Mute")

            Slider(value: Binding(
                get: { audio.volume },
                set: { audio.setVolume($0) }
            ), in: 0...1)
            .tint(.white)

            Menu {
                ForEach(audio.outputs) { output in
                    Button {
                        audio.selectOutput(output)
                    } label: {
                        if output.name == audio.outputName {
                            Label(output.name, systemImage: "checkmark")
                        } else {
                            Text(output.name)
                        }
                    }
                }
            } label: {
                Label("Output", systemImage: "speaker.wave.2.fill")
                    .labelStyle(.iconOnly)
                    .frame(width: 18)
            }
            .help("Audio output: \(audio.outputName)")
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.78))
        .padding(.horizontal, 3)
        .onAppear { audio.refresh() }
    }
}
