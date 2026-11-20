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
    /// The device this muter silenced, so the same one is restored even if
    /// the default output changes mid-dictation.
    private var muted: AudioDeviceID?

    /// Does nothing if output is already muted, by the user or by an earlier
    /// call: restoring must never unmute something the user muted.
    func mute() {
        guard muted == nil, let device = Self.defaultOutput(), Self.isMuted(device) == false else { return }
        if Self.setMuted(true, on: device) { muted = device }
    }

    func restore() {
        guard let device = muted else { return }
        muted = nil
        Self.setMuted(false, on: device)
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

    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain)

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
