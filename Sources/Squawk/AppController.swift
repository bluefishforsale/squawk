// Wires hotkey, recorder, model and paste together and owns the menu-bar
// item, which is the app's only permanent UI.

import AVFoundation
import AppKit
import SquawkCore
import SwiftUI

final class AppController: NSObject, NSApplicationDelegate {
    private enum Status {
        case idle
        case recording
        case working
        case problem(String)
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let hotkeys = HotkeyMonitor()
    private let recorder = Recorder()
    private let transcriber = Transcriber()
    private var gesture = HoldGesture()
    private var unloadTimer: Timer?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()

        let menu = NSMenu()
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit Squawk", action: #selector(NSApplication.terminate), keyEquivalent: "q")
        statusItem.menu = menu
        show(.idle)

        hotkeys.onHotkeyDown = { [unowned self] in perform(gesture.keyDown(at: ProcessInfo.processInfo.systemUptime)) }
        hotkeys.onHotkeyUp = { [unowned self] in perform(gesture.keyUp(at: ProcessInfo.processInfo.systemUptime)) }
        hotkeys.onOtherKeyDown = { [unowned self] in perform(gesture.otherKeyDown()) }

        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(prompt)
        installHotkeyTap()
    }

    /// The tap cannot be created until Accessibility is granted, and macOS
    /// sends no notification when that happens, so poll.
    private func installHotkeyTap() {
        guard !hotkeys.start() else { return show(.idle) }
        show(.problem("Grant Accessibility in System Settings, Privacy & Security"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.installHotkeyTap() }
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
            // Warm the model while the user is still talking.
            Task { try? await transcriber.prepare() }
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
        Task { @MainActor in
            do {
                let text = cleanup.apply(try await transcriber.transcribe(samples))
                if !text.isEmpty {
                    TextInserter.paste(text + " ")
                }
                show(.idle)
            } catch {
                show(.problem("Transcription: \(error.localizedDescription)"))
            }
            scheduleUnload()
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
        let symbol: String
        let tint: NSColor?
        switch status {
        case .idle:
            (symbol, tint) = ("mic", nil)
            statusLine.title = "Hold \(Preferences.hotkey.label) to dictate"
        case .recording:
            (symbol, tint) = ("mic.fill", .systemRed)
            statusLine.title = "Listening…"
        case .working:
            (symbol, tint) = ("ellipsis", nil)
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
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
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
