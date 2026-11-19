// Entry point. Normally a menu-bar app; `--transcribe <audio file>` runs one
// file through the same model path and exits, which is how CI and the memory
// benchmark exercise Parakeet without microphone or accessibility grants.

import AppKit
import FluidAudio

if let flag = CommandLine.arguments.firstIndex(of: "--transcribe"),
    CommandLine.arguments.count > flag + 1
{
    let path = CommandLine.arguments[flag + 1]
    Task {
        do {
            let samples = try AudioConverter().resampleAudioFile(URL(fileURLWithPath: path))
            print(try await Transcriber().transcribe(samples))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("squawk: \(path): \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    dispatchMain()
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
