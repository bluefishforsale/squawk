// Wires shortcut, recorder, models and paste together and owns the menu-bar
// item, which is the app's only permanent UI.

import AVFoundation
import AppKit
import SquawkCore
import SwiftUI
import os

/// Read with: /usr/bin/log show --last 5m --predicate 'subsystem == "com.bluefishforsale.squawk"'
/// Never logs what was said, only sizes and state changes.
let log = Logger(subsystem: "com.bluefishforsale.squawk", category: "app")

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
    private let overlay = ListeningOverlay()
    private let transcriber = Transcriber()
    private var gesture = HoldGesture()
    private var status = Status.preparing
    private var isLearningShortcut = false
    private var unloadTimer: Timer?
    private var pendingFinish: DispatchWorkItem?
    /// The app the last dictation went into, cleared as soon as the user types
    /// or clicks. While it is set, the cursor is still right after that text.
    private var continuingIn: pid_t?
    private var lastPasteAt: TimeInterval = 0
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
            if edge != .chord {
                log.notice("shortcut edge: \(String(describing: edge), privacy: .public)")
            }
            let now = ProcessInfo.processInfo.systemUptime
            switch edge {
            case .down: perform(gesture.keyDown(at: now))
            case .up: perform(gesture.keyUp(at: now))
            case .chord: perform(gesture.otherKeyDown())
            }
        }
        hotkeys.onUserInput = { [unowned self] in
            // The paste's own Cmd+V arrives back through the tap a moment
            // after it is posted; it must not count as the user typing.
            guard ProcessInfo.processInfo.systemUptime - lastPasteAt > 0.4 else { return }
            continuingIn = nil
        }
        recorder.onLevel = { [overlay] rms in overlay.history.push(rms: rms) }
        overlay.prepare()
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
        guard !hotkeys.start() else {
            log.notice("event tap installed, trusted=\(AXIsProcessTrusted(), privacy: .public)")
            return show(.idle)
        }
        log.notice("event tap refused, trusted=\(AXIsProcessTrusted(), privacy: .public)")
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
        overlay.hide()
        gesture = HoldGesture()
        if case .recording = status { show(.idle) }
    }

    @objc private func toggleEnabled() {
        Preferences.isEnabled.toggle()
    }

    private func perform(_ action: HoldGesture.Action?) {
        if let action {
            log.notice("gesture: \(String(describing: action), privacy: .public)")
        }
        switch action {
        case .start:
            flushPendingFinish()
            // Opening the microphone blocks for 150 ms or more, so the overlay
            // goes up and is pushed to the screen before that starts.
            show(.recording)
            overlay.show()
            CATransaction.flush()
            playSound("Tink")
            do {
                try recorder.start()
            } catch {
                overlay.hide()
                return show(.problem("Microphone: \(error.localizedDescription)"))
            }
            unloadTimer?.invalidate()
            // Warm the models while the user is still talking.
            Task { try? await transcriber.prepare(names: Preferences.names) }
        case .discard:
            recorder.cancel()
            overlay.hide()
            show(.idle)
            scheduleUnload()
        case .finish:
            // Keep listening a moment past key release: people let go on the
            // last syllable, and the tail of that word is still in the air.
            show(.working)
            overlay.hide()
            playSound("Pop")
            let work = DispatchWorkItem { [unowned self] in
                pendingFinish = nil
                finish()
            }
            pendingFinish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        case nil:
            break
        }
    }

    private func playSound(_ name: String) {
        guard Preferences.playSounds else { return }
        NSSound(named: name)?.play()
    }

    private func flushPendingFinish() {
        guard let work = pendingFinish else { return }
        work.perform()
        work.cancel()
    }

    private func finish() {
        let samples: [Float]
        do {
            samples = try recorder.stop()
        } catch {
            return show(.problem("Audio: \(error.localizedDescription)"))
        }
        log.notice("recorded \(samples.count, privacy: .public) samples at 16 kHz")
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
                log.notice("transcribed \(output.text.count, privacy: .public) characters, pasting \(text.count, privacy: .public)")
                if !text.isEmpty {
                    TextInserter.paste(text, leadingSpace: cleanup.spaceAfterPunctuation && needsLeadingSpace(text))
                    continuingIn = NSWorkspace.shared.frontmostApplication?.processIdentifier
                    lastPasteAt = ProcessInfo.processInfo.systemUptime
                }
                show(output.warning.map(Status.problem) ?? .idle)
            } catch {
                show(.problem("Transcription: \(error.localizedDescription)"))
            }
            scheduleUnload()
        }
    }

    /// Whether the text about to be pasted follows directly on other text, so
    /// that back-to-back dictations do not run together as "one.Two".
    private func needsLeadingSpace(_ text: String) -> Bool {
        guard let first = text.first, !first.isPunctuation else { return false }
        // Squawk's own knowledge comes first: it just dictated into this app
        // and nothing was typed or clicked since, so the cursor sits right
        // after that text. Terminals answer the accessibility query below with
        // nonsense (position zero, or a blank cell), so it cannot be trusted
        // to overrule this.
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let continuing = continuingIn != nil && continuingIn == frontmost
        var before: Character?
        if case .some(.some(let character)) = TextInserter.characterBeforeCursor() {
            before = character
        }
        let afterText = before.map { !$0.isWhitespace && !"([{\"'“‘".contains($0) } ?? false
        log.notice("leading space: continuing=\(continuing, privacy: .public) afterText=\(afterText, privacy: .public)")
        return continuing || afterText
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
        if case .problem(let message) = status {
            log.error("problem: \(message, privacy: .public)")
        }
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
        // A template image is drawn by macOS in whatever contrasts with the
        // menu bar, light or dark. Only the two alert states carry a color.
        var image = NSImage(systemSymbolName: symbol, accessibilityDescription: statusLine.title)
        if let tint {
            image = image?.withSymbolConfiguration(.init(paletteColors: [tint]))
        }
        image?.isTemplate = tint == nil
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = nil
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
