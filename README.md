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
recording away. The menu has an Enabled switch for when you want the key back.

To change the key, click the keycaps in Settings and press what you want: one
modifier, several held together, or modifiers plus an ordinary key. Left and
right modifiers count as different keys. A bare letter is refused, since it
would stop you typing that letter; F-keys are fine on their own.

Squawk pastes what you said, minus the noise. Um and uh go, stuttered words
collapse, and spacing after punctuation is fixed. An optional setting drops
filler "like" and turns "she was like," into "she said,". None of it rephrases:
there is no language model rewriting your sentences, only rules that each need
a clear signal before they fire. `spoken => written` replacements cover jargon.

Names get their own treatment, because that is where recognition fails most.
Add a name in Settings with the spellings it comes out as ("Terrac", sounds
like "terek, tarik"), or click Train and say it, and Squawk adds whatever it
heard. From then on, whenever a transcript contains something resembling the
name, a second small model re-listens to that stretch of audio and decides
between the two. A real Derek or a real terrace stays as it is.

The first launch downloads the Parakeet model (about 470 MB) from Hugging Face
into `~/Library/Application Support/FluidAudio`, and adding your first name
downloads a 100 MB companion model the same way. Those are the only network
requests the app ever makes. Otherwise Squawk runs with FluidAudio's offline
mode on. The first launch of each new version also spends about half a
minute compiling the model for the Neural Engine, shown as "Preparing speech
model" in the menu; after that a load takes a fraction of a second.

## Building

You need macOS 14 or later on Apple Silicon and a Swift 6 toolchain; the
command line tools are enough, Xcode is not required.

    swift test
    scripts/bundle.sh
    open dist/Squawk.app

`scripts/bundle.sh` signs with the first Developer ID in your keychain, and
falls back to an ad-hoc signature when there is none. The difference matters:
macOS remembers the Accessibility and Microphone grants against the signing
identity, so a Developer ID build keeps them across rebuilds and updates, and
an ad-hoc build loses them every time.

## Releasing

Pushing a `v*` tag runs `.github/workflows/release.yml`, which builds the app
in a job with no secrets, then signs, notarizes and staples it in the `release`
environment and publishes the DMG. Only `v*` tags can deploy to that
environment. It needs these secrets there, the same set and the same Apple
identity that gemdigger and signal-agent use: `APPLE_CERTIFICATE`,
`APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_TEAM_ID`,
`APPLE_API_ISSUER`, `APPLE_API_KEY`, `APPLE_API_PRIVATE_KEY`, and a random
`KEYCHAIN_PASSWORD`. A tag pushed while any is missing fails at the first job,
before anything is built.

Pull request builds are ad-hoc signed and are for testing only.

To run a file through the same model path without the UI, which is handy for
checking memory and speed:

    /usr/bin/time -l dist/Squawk.app/Contents/MacOS/Squawk --transcribe sample.wav
    dist/Squawk.app/Contents/MacOS/Squawk --transcribe sample.wav --name "Terrac=terek,tarik"

## License

GPL-3.0. Speech recognition comes from
[FluidAudio](https://github.com/FluidInference/FluidAudio) (Apache-2.0) and
NVIDIA's Parakeet TDT 0.6B v3.
