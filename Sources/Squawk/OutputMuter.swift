// Silences the Mac's audio output for the length of a dictation, so a video
// or music coming out of the speakers is not transcribed along with the
// voice. Playback itself keeps running; it is just not heard for a moment.
//
// This is deliberately not echo cancellation. macOS voice processing was
// tried first: it took about 1.5 s to start on every dictation, made
// playback in other apps stutter and swing in volume, and often delivered
// no microphone audio at all.

import CoreAudio
import Foundation

final class OutputMuter {
    private struct Silenced {
        let device: AudioDeviceID
        /// The volume to put back, or nil if the mute switch was used.
        let volume: Float32?
    }

    /// Survives a crash: if Squawk dies mid-dictation the next launch puts
    /// the volume back.
    private static let savedVolumeKey = "volumeToRestore"
    private var silenced: Silenced?

    init() {
        let saved = UserDefaults.standard.object(forKey: Self.savedVolumeKey) as? Float
        guard let saved, let device = Self.defaultOutput() else { return }
        Self.setVolume(saved, on: device)
        UserDefaults.standard.removeObject(forKey: Self.savedVolumeKey)
    }

    func mute() {
        guard silenced == nil, let device = Self.defaultOutput() else { return }
        // NOTE: volume first, not the mute switch. Some outputs accept the
        // mute command and carry on playing: a USB soundbar reported itself
        // muted while the microphone heard it exactly as loud as before.
        // Turning the volume to zero worked on the same device.
        if let volume = Self.volume(of: device) {
            guard volume > 0 else { return }
            UserDefaults.standard.set(volume, forKey: Self.savedVolumeKey)
            if Self.setVolume(0, on: device) {
                silenced = Silenced(device: device, volume: volume)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.savedVolumeKey)
            }
        } else if Self.isMuted(device) == false, Self.setMuted(true, on: device) {
            // Never reached for output the user had already muted, so the
            // restore below cannot unmute something they silenced.
            silenced = Silenced(device: device, volume: nil)
        }
    }

    func restore() {
        guard let silenced else { return }
        self.silenced = nil
        if let volume = silenced.volume {
            // Only if it is still at zero: if the user turned it up during
            // the dictation, their setting wins.
            if Self.volume(of: silenced.device) == 0 { Self.setVolume(volume, on: silenced.device) }
            UserDefaults.standard.removeObject(forKey: Self.savedVolumeKey)
        } else {
            Self.setMuted(false, on: silenced.device)
        }
    }

    private static func defaultOutput() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    /// The same control the volume keys move ('vmvc', the device's virtual
    /// main volume), which exists even where there is no single hardware
    /// volume channel.
    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: 0x766D_7663, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

    /// Nil when the device has no volume the system can set.
    private static func volume(of device: AudioDeviceID) -> Float32? {
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &volumeAddress),
            AudioObjectIsPropertySettable(device, &volumeAddress, &settable) == noErr, settable.boolValue,
            AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &value) == noErr
        else { return nil }
        return value
    }

    @discardableResult
    private static func setVolume(_ volume: Float32, on device: AudioDeviceID) -> Bool {
        var value = volume
        return AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    /// Nil when the device has no mute control, as some HDMI outputs do not.
    private static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectHasProperty(device, &muteAddress),
            AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &value) == noErr
        else { return nil }
        return value != 0
    }

    @discardableResult
    private static func setMuted(_ muted: Bool, on device: AudioDeviceID) -> Bool {
        var value: UInt32 = muted ? 1 : 0
        return AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}
