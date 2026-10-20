import Combine
import CoreAudio
import Foundation

/// What the controller needs to know about where the sound goes: its name, whether it is
/// muted, and whether Shut could lift that mute. Read-only except `setMuted`, which only
/// "Unmute for it" ever calls, and which always gets undone.
protocol OutputMuting: AnyObject {
    var deviceName: String? { get }
    var deviceUID: String? { get }
    /// Muted, or the volume all the way down: either way nothing would be heard.
    var isMuted: Bool { get }
    /// Some outputs (Bluetooth, HDMI) have no mute control Shut can reach.
    var canSetMute: Bool { get }
    @discardableResult func setMuted(_ muted: Bool) -> Bool
    /// The output's volume, 0…1; nil when the device has none Shut can read.
    var volume: Float? { get }
    var canSetVolume: Bool { get }
    /// Only "Its own level" ever calls this, and always puts the old value back.
    @discardableResult func setVolume(_ volume: Float) -> Bool
    /// Calls back on the main queue when the default output or its mute changes. The
    /// listener exists only while something is listening (the panel is open).
    func listen(_ onChange: @escaping () -> Void) -> AnyCancellable
}

/// The default output device through CoreAudio. One property read per question, nothing
/// cached, so it is always what the Mac says right now.
final class CoreAudioOutput: OutputMuting {
    private var defaultDevice: AudioObjectID? {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    private static let muteAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                                                mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static let volumeAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                                  mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    /// Some devices keep volume per channel and have no main element; channel 1 then stands in.
    private static let channelVolumeAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                                         mScope: kAudioObjectPropertyScopeOutput, mElement: 1)

    private func string(_ selector: AudioObjectPropertySelector, of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    var deviceName: String? { defaultDevice.flatMap { string(kAudioObjectPropertyName, of: $0) } }
    var deviceUID: String? { defaultDevice.flatMap { string(kAudioDevicePropertyDeviceUID, of: $0) } }

    private func uint32(_ address: AudioObjectPropertyAddress, of device: AudioObjectID) -> UInt32? {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    private func float(_ address: AudioObjectPropertyAddress, of device: AudioObjectID) -> Float32? {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }

    var isMuted: Bool {
        guard let device = defaultDevice else { return false }
        if uint32(Self.muteAddress, of: device) == 1 { return true }
        return volume.map { $0 <= 0.001 } ?? false
    }

    var volume: Float? {
        guard let device = defaultDevice else { return nil }
        return float(Self.volumeAddress, of: device) ?? float(Self.channelVolumeAddress, of: device)
    }

    private static let secondChannelVolumeAddress = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                                               mScope: kAudioObjectPropertyScopeOutput, mElement: 2)

    private func settable(_ address: AudioObjectPropertyAddress, of device: AudioObjectID) -> Bool {
        var address = address
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    var canSetVolume: Bool {
        guard let device = defaultDevice else { return false }
        return settable(Self.volumeAddress, of: device) || settable(Self.channelVolumeAddress, of: device)
    }

    /// The main element when the device has one; otherwise both channels, as the menu bar does.
    @discardableResult
    func setVolume(_ volume: Float) -> Bool {
        guard let device = defaultDevice else { return false }
        var value = max(0, min(1, volume))
        let size = UInt32(MemoryLayout<Float32>.size)
        if settable(Self.volumeAddress, of: device) {
            var address = Self.volumeAddress
            return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
        }
        var done = false
        for channel in [Self.channelVolumeAddress, Self.secondChannelVolumeAddress] where settable(channel, of: device) {
            var address = channel
            done = AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr || done
        }
        return done
    }

    var canSetMute: Bool {
        guard let device = defaultDevice else { return false }
        var address = Self.muteAddress
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &address)
            && AudioObjectIsPropertySettable(device, &address, &settable) == noErr && settable.boolValue
    }

    @discardableResult
    func setMuted(_ muted: Bool) -> Bool {
        guard let device = defaultDevice, canSetMute else { return false }
        var address = Self.muteAddress
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }

    func listen(_ onChange: @escaping () -> Void) -> AnyCancellable {
        var defaultAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var listened: (device: AudioObjectID, block: AudioObjectPropertyListenerBlock)?
        func listenToMute() {
            if let old = listened {
                var address = Self.muteAddress
                AudioObjectRemovePropertyListenerBlock(old.device, &address, DispatchQueue.main, old.block)
                listened = nil
            }
            guard let device = defaultDevice else { return }
            let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
            var address = Self.muteAddress
            if AudioObjectAddPropertyListenerBlock(device, &address, DispatchQueue.main, block) == noErr {
                listened = (device, block)
            }
        }
        let onDefaultChange: AudioObjectPropertyListenerBlock = { _, _ in listenToMute(); onChange() }
        AudioObjectAddPropertyListenerBlock(system, &defaultAddress, DispatchQueue.main, onDefaultChange)
        listenToMute()
        return AnyCancellable {
            var address = defaultAddress
            AudioObjectRemovePropertyListenerBlock(system, &address, DispatchQueue.main, onDefaultChange)
            if let old = listened {
                var muteAddress = Self.muteAddress
                AudioObjectRemovePropertyListenerBlock(old.device, &muteAddress, DispatchQueue.main, old.block)
            }
        }
    }
}
