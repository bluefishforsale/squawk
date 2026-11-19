// The whole settings surface. Anything that would need a second pane does not
// belong in this app.

import ServiceManagement
import SquawkCore
import SwiftUI

enum Preferences {
    static let enabledKey = "enabled"
    static let bindingKey = "binding"
    static let namesKey = "names"
    static let removeFillersKey = "removeFillers"
    static let rewriteLikeKey = "rewriteLike"
    static let spaceAfterPunctuationKey = "spaceAfterPunctuation"
    static let endWithPeriodKey = "endWithPeriod"
    static let playSoundsKey = "playSounds"
    static let replacementsKey = "replacements"
    static let unloadMinutesKey = "unloadMinutes"

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            enabledKey: true,
            removeFillersKey: true,
            rewriteLikeKey: false,
            spaceAfterPunctuationKey: true,
            endWithPeriodKey: true,
            playSoundsKey: true,
            unloadMinutesKey: 10,
        ])
    }

    static var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    static var binding: KeyBinding {
        get { decoded(bindingKey) ?? .rightOption }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: bindingKey) }
    }

    static var names: [NameEntry] {
        get { decoded(namesKey) ?? [] }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: namesKey) }
    }

    static var cleanup: TextCleanup {
        TextCleanup(
            removeFillers: defaults.bool(forKey: removeFillersKey),
            rewriteLike: defaults.bool(forKey: rewriteLikeKey),
            spaceAfterPunctuation: defaults.bool(forKey: spaceAfterPunctuationKey),
            endWithPeriod: defaults.bool(forKey: endWithPeriodKey),
            replacements: Replacement.parse(defaults.string(forKey: replacementsKey) ?? ""))
    }

    static var playSounds: Bool {
        defaults.bool(forKey: playSoundsKey)
    }

    /// Zero keeps the model loaded forever.
    static var unloadMinutes: Int {
        defaults.integer(forKey: unloadMinutesKey)
    }

    private static func decoded<Value: Decodable>(_ key: String) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }
}

struct SettingsView: View {
    /// Pauses the global shortcut while a new one is being learned.
    let setLearning: (Bool) -> Void
    /// Records a couple of seconds and returns what the recognizer heard,
    /// without name correction, for training a name.
    let hear: () async -> String?

    @AppStorage(Preferences.enabledKey) private var enabled = true
    @AppStorage(Preferences.removeFillersKey) private var removeFillers = true
    @AppStorage(Preferences.rewriteLikeKey) private var rewriteLike = false
    @AppStorage(Preferences.spaceAfterPunctuationKey) private var spaceAfterPunctuation = true
    @AppStorage(Preferences.endWithPeriodKey) private var endWithPeriod = true
    @AppStorage(Preferences.playSoundsKey) private var playSounds = true
    @AppStorage(Preferences.replacementsKey) private var replacements = ""
    @AppStorage(Preferences.unloadMinutesKey) private var unloadMinutes = 10
    @State private var binding = Preferences.binding
    @State private var names = Preferences.names
    @State private var trainingName: UUID?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Dictation key")
                    Spacer()
                    ShortcutRecorder(binding: $binding, setLearning: setLearning)
                    Toggle("Enabled", isOn: $enabled).labelsHidden()
                }
                Text("Hold to dictate. Double-tap to lock hands-free, tap again to stop.")
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle("Play a sound when listening starts and stops", isOn: $playSounds)
            }
            .onChange(of: binding) { _, new in Preferences.binding = new }

            Section("Cleanup") {
                Toggle("Remove um, uh and stuttered words", isOn: $removeFillers)
                Toggle("Remove filler \"like\", and turn \"she was like\" into \"she said\"", isOn: $rewriteLike)
                Toggle("Add a space after punctuation and between dictations", isOn: $spaceAfterPunctuation)
                Toggle("End each dictation with a full stop if it has none", isOn: $endWithPeriod)
            }

            Section {
                ForEach($names) { $entry in
                    HStack {
                        TextField("Name", text: $entry.text).frame(width: 110)
                        TextField("Sounds like: terek, tarik", text: $entry.soundsLike)
                        Button(trainingName == entry.id ? "Listening…" : "Train") { train(entry.id) }
                            .disabled(trainingName != nil || entry.name.isEmpty)
                            .help("Click, then say the name. What Squawk hears is added as a sound-alike.")
                        Button {
                            names.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                    }
                    .labelsHidden()
                }
                Button("Add name") { names.append(NameEntry()) }
            } header: {
                Text("Names")
            } footer: {
                Text("Squawk re-listens to the audio whenever it hears a name or one of its sound-alikes.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .onChange(of: names) { _, new in Preferences.names = new }

            Section("Replacements, one per line: spoken => written") {
                TextEditor(text: $replacements)
                    .font(.body.monospaced())
                    .frame(height: 70)
            }

            Section {
                Picker("Free model memory after", selection: $unloadMinutes) {
                    Text("1 minute idle").tag(1)
                    Text("10 minutes idle").tag(10)
                    Text("1 hour idle").tag(60)
                    Text("Never").tag(0)
                }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                        }
                    }
                if let loginError {
                    Text(loginError).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize()
    }

    private func train(_ id: UUID) {
        trainingName = id
        Task { @MainActor in
            let heard = await hear()
            if let heard, let index = names.firstIndex(where: { $0.id == id }) {
                names[index].learn(heard: heard)
            }
            trainingName = nil
        }
    }
}

struct Keycaps: View {
    let labels: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: .black.opacity(0.35), radius: 0, y: 1)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.4)))
            }
        }
    }
}

/// Click, press the keys you want, let go. Escape cancels.
struct ShortcutRecorder: View {
    @Binding var binding: KeyBinding
    let setLearning: (Bool) -> Void

    @State private var monitor: Any?
    @State private var held: UInt64 = 0
    @State private var down: UInt64 = 0
    @State private var rejected = false

    var body: some View {
        Button {
            monitor == nil ? begin() : end()
        } label: {
            if monitor == nil {
                Keycaps(labels: binding.keycaps)
            } else {
                Text(rejected ? "Add a modifier, or use an F-key" : "Press keys…")
                    .foregroundStyle(rejected ? .red : .secondary)
            }
        }
        .buttonStyle(.plain)
        .help("Click, then press the key or keys to hold for dictation")
        .onDisappear(perform: end)
    }

    private func begin() {
        held = 0
        down = 0
        rejected = false
        setLearning(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            if event.type == .keyDown {
                guard event.keyCode != 53 else {
                    end()
                    return nil
                }
                // NOTE: use the modifiers seen going down, not the key event's
                // own flags. macOS sets the fn flag on every F-key and arrow
                // press, which once saved F16 as "fn + F16" and made it
                // impossible to trigger.
                commit(KeyBinding(modifiers: down, keyCode: event.keyCode, keyLabel: Self.label(for: event)))
                return nil
            }
            down = UInt64(event.modifierFlags.rawValue) & ModifierKey.allMasks
            if down == 0, held != 0 {
                // Modifier-only shortcut: take the most keys that were down
                // together, committed when the last one is released.
                commit(KeyBinding(modifiers: held))
            } else {
                held |= down
            }
            return nil
        }
    }

    private func commit(_ candidate: KeyBinding) {
        guard candidate.isUsable else {
            held = 0
            rejected = true
            return
        }
        binding = candidate
        end()
    }

    private func end() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        setLearning(false)
    }

    private static let namedKeys: [UInt16: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 117: "Fwd Delete", 76: "Enter",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    private static func label(for event: NSEvent) -> String {
        namedKeys[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "key \(event.keyCode)"
    }
}
