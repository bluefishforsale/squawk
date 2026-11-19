// Entry point. Normally a menu-bar app; `--transcribe <audio file>` runs one
// file through the same model path and exits, which is how CI and the memory
// benchmark exercise the models without microphone or accessibility grants.
// Add `--name "Terrac=terek,tarik"` (repeatable) to test name correction.
// `--install-update <dmg file>` runs the self-update path against a local
// disk image, with the same signature and version checks as a real update.
// `--check-model` reports whether Hugging Face has newer weights than the
// ones on disk, and `--install-model <revision>` installs that revision.
// `--render-panes <folder>` writes a PNG of each pane of the panel, which is
// how the README screenshots are made (see scripts/screenshots.sh).

import AppKit
import FluidAudio
import SquawkCore

let arguments = CommandLine.arguments

func values(after flag: String) -> [String] {
    arguments.indices.dropLast().filter { arguments[$0] == flag }.map { arguments[$0 + 1] }
}

if let path = values(after: "--transcribe").first {
    let names = values(after: "--name").map { spec in
        let parts = spec.split(separator: "=", maxSplits: 1).map(String.init)
        return NameEntry(text: parts[0], soundsLike: parts.count > 1 ? parts[1] : "")
    }
    Task {
        do {
            let samples = try AudioConverter().resampleAudioFile(URL(fileURLWithPath: path))
            let output = try await Transcriber().transcribe(samples, names: names)
            if let warning = output.warning {
                FileHandle.standardError.write(Data("squawk: \(warning)\n".utf8))
            }
            print(output.text)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("squawk: \(path): \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    dispatchMain()
}

if let path = values(after: "--install-update").first, let version = AppVersion("0") {
    let file = URL(fileURLWithPath: path)
    Task {
        do {
            try await Updater.install(AvailableUpdate(version: version, dmg: file, page: file))
        } catch {
            FileHandle.standardError.write(Data("squawk: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    dispatchMain()
}

if arguments.contains("--check-model") {
    Task {
        do {
            let update = try await ModelStore.check()
            print("installed:", ModelStore.active.revision ?? "first download", "| update:", update?.revision ?? "none")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("squawk: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    dispatchMain()
}

if let revision = values(after: "--install-model").first {
    Task {
        do {
            try await Transcriber().install(revision: revision) { fraction in
                FileHandle.standardError.write(Data("\r\(Int(fraction * 100))%".utf8))
            }
            print("\ninstalled:", ModelStore.active.revision ?? "first download")
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("\nsquawk: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
    dispatchMain()
}

if let folder = values(after: "--render-panes").first {
    PaneRenderer.render(into: URL(fileURLWithPath: folder, isDirectory: true))
    exit(0)
}

let app = NSApplication.shared
let controller = AppController()
app.delegate = controller
app.setActivationPolicy(.accessory)
app.run()
