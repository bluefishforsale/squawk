// Wires shortcut, recorder, models and paste together and owns the menu-bar
// item, which is the app's only permanent UI.

import AVFoundation
import AppKit
import SquawkCore
import SwiftUI

final class AppController: NSObject, NSApplicationDelegate {
    private enum Status {
        case preparing
        case idle
        case recording
        case working
        case problem(String)
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private lazy var hotkeys = HotkeyMonitor(binding: Preferences.binding)
    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private var gesture = HoldGesture()
    private var status = Status.preparing
    private var isLearningShortcut = false
    private var unloadTimer: Timer?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()

        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        enabledItem.target = self
        menu.addItem(enabledItem)
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Squawk", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        statusItem.menu = menu

        hotkeys.onEdge = { [unowned self] edge in
            let now = ProcessInfo.processInfo.systemUptime
            switch edge {
            case .down: perform(gesture.keyDown(at: now))
            case .up: perform(gesture.keyUp(at: now))
            case .chord: perform(gesture.otherKeyDown())
            }
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferencesChanged), name: UserDefaults.didChangeNotification, object: nil)
        preferencesChanged()

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(prompt)
        warmModel()
    }

    /// CoreML compiles the encoder for the Neural Engine the first time a given
    /// build of the app loads it, which takes around half a minute. Paying that
    /// at launch keeps it out of the first dictation; the idle timer then frees
    /// the memory again.
    private func warmModel() {
        show(.preparing)
        Task { @MainActor in
            do {
                try await transcriber.prepare(names: Preferences.names)
                installHotkeyTap()
            } catch {
                // Still install the tap: the next key press retries the load.
                installHotkeyTap()
                show(.problem("Speech model: \(error.localizedDescription)"))
            }
            scheduleUnload()
        }
    }

    /// The tap cannot be created until Accessibility is granted, and macOS
    /// sends no notification when that happens, so poll.
    private func installHotkeyTap() {
        guard !hotkeys.start() else { return show(.idle) }
        show(.problem("Grant Accessibility in System Settings, Privacy & Security"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.installHotkeyTap() }
    }

    @objc private func preferencesChanged() {
        DispatchQueue.main.async { [self] in
            hotkeys.binding = Preferences.binding
            applyPause()
            show(status)
        }
    }

    private func applyPause() {
        let paused = !Preferences.isEnabled || isLearningShortcut
        guard paused != hotkeys.isPaused else { return }
        hotkeys.isPaused = paused
        guard paused else { return }
        // Whatever was in flight when dictation was switched off is dropped.
        recorder.cancel()
        gesture = HoldGesture()
        if case .recording = status { show(.idle) }
    }

    @objc private func toggleEnabled() {
        Preferences.isEnabled.toggle()
    }

    private func perform(_ action: HoldGesture.Action?) {
        switch action {
        case .start:
            do {
                try recorder.start()
            } catch {
                return show(.problem("Microphone: \(error.localizedDescription)"))
            }
            show(.recording)
            unloadTimer?.invalidate()
            // Warm the models while the user is still talking.
            Task { try? await transcriber.prepare(names: Preferences.names) }
        case .discard:
            recorder.cancel()
            show(.idle)
            scheduleUnload()
        case .finish:
            finish()
        case nil:
            break
        }
    }

    private func finish() {
        let samples: [Float]
        do {
            samples = try recorder.stop()
        } catch {
            return show(.problem("Audio: \(error.localizedDescription)"))
        }
        guard samples.count >= Transcriber.minimumSamples else {
            show(.idle)
            return scheduleUnload()
        }
        show(.working)
        let cleanup = Preferences.cleanup
        let names = Preferences.names
        Task { @MainActor in
            do {
                let output = try await transcriber.transcribe(samples, names: names)
                let text = cleanup.apply(output.text)
                if !text.isEmpty {
                    // The trailing space keeps back-to-back dictations from
                    // running together as "one.Two".
                    TextInserter.paste(cleanup.spaceAfterPunctuation ? text + " " : text)
                }
                show(output.warning.map(Status.problem) ?? .idle)
            } catch {
                show(.problem("Transcription: \(error.localizedDescription)"))
            }
            scheduleUnload()
        }
    }

    /// Settings' Train button: listen briefly and report what the recognizer
    /// wrote, with name correction off so the raw mishearing comes back.
    private func hear() async -> String? {
        do {
            try recorder.start()
            try await Task.sleep(for: .seconds(2.5))
            let samples = try recorder.stop()
            guard samples.count >= Transcriber.minimumSamples else { return nil }
            let heard = try await transcriber.transcribe(samples).text
            scheduleUnload()
            return heard
        } catch {
            recorder.cancel()
            show(.problem("Training: \(error.localizedDescription)"))
            return nil
        }
    }

    private func scheduleUnload() {
        unloadTimer?.invalidate()
        let minutes = Preferences.unloadMinutes
        guard minutes > 0 else { return }
        unloadTimer = .scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [transcriber] _ in
            Task { await transcriber.unload() }
        }
    }

    private func show(_ status: Status) {
        self.status = status
        let enabled = Preferences.isEnabled
        enabledItem.state = enabled ? .on : .off

        let symbol: String
        var tint: NSColor?
        switch status {
        case .preparing:
            symbol = "arrow.down.circle"
            statusLine.title = "Preparing speech model…"
        case .idle:
            symbol = enabled ? "mic" : "mic.slash"
            statusLine.title =
                enabled ? "Hold \(Preferences.binding.keycaps.joined(separator: " + ")) to dictate" : "Dictation is off"
        case .recording:
            (symbol, tint) = ("mic.fill", .systemRed)
            statusLine.title = "Listening…"
        case .working:
            symbol = "ellipsis"
            statusLine.title = "Transcribing…"
        case .problem(let message):
            (symbol, tint) = ("exclamationmark.triangle", .systemYellow)
            statusLine.title = message
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: statusLine.title)
        statusItem.button?.contentTintColor = tint
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                setLearning: { [unowned self] learning in
                    isLearningShortcut = learning
                    applyPause()
                },
                hear: { [unowned self] in await hear() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Squawk"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
