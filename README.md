# Squawk

Hold a key, talk, let go, and the words land wherever your cursor is. Squawk is
a free dictation app for Apple Silicon Macs that runs NVIDIA's Parakeet model
on the Neural Engine and never sends audio or text off the machine.

It exists because the paid apps in this space do the transcription part well
and then keep going: meeting notes, command modes, cloud keys, sync. Squawk
stops at dictation, and the payoff is a menu-bar app that sits at a few tens of
megabytes and drops its model from memory when you stop talking for a while.

## Using it

Download the DMG from the releases page, drag Squawk to Applications, and open
it. macOS asks for two permissions: Microphone, to hear you, and Accessibility,
to watch the dictation key and paste the result. A microphone icon appears in
the menu bar and that is the entire interface.

Hold Right Option and speak; release to paste. Double-tap the key to lock
recording hands-free and tap once more to stop. If you press another key while
holding it, Squawk assumes you meant a keyboard shortcut and throws the
recording away. Settings lets you pick a different key, turn filler-word
removal off, add `spoken => written` replacements for names and jargon, and
choose how long the model stays in memory after you stop talking.

The first launch downloads the Parakeet model (about 470 MB) from Hugging Face
into `~/Library/Application Support/FluidAudio`. That is the only network
request the app ever makes. After it, Squawk sets FluidAudio's offline mode on
every launch. The first launch of each new version also spends about half a
minute compiling the model for the Neural Engine, shown as "Preparing speech
model" in the menu; after that a load takes a fraction of a second.

## Building

You need macOS 14 or later on Apple Silicon and a Swift 6 toolchain; the
command line tools are enough, Xcode is not required.

    swift test
    scripts/bundle.sh
    open dist/Squawk.app

A local build is ad-hoc signed, so macOS treats each rebuild as a new app and
asks for Accessibility again. Release builds are signed with a Developer ID and
notarized by `.github/workflows/release.yml` when a `v*` tag is pushed.

To run a file through the same model path without the UI, which is handy for
checking memory and speed:

    /usr/bin/time -l dist/Squawk.app/Contents/MacOS/Squawk --transcribe sample.wav

## License

GPL-3.0. Speech recognition comes from
[FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache-2.0) and
NVIDIA's Parakeet TDT 0.6B v3.
