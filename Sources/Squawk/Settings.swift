// Stored preferences, and the panel under the menu bar icon that edits them.
// Anything that would need a second pane does not belong in this app.

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
    static let microphoneKey = "microphone"
    static let replacementsKey = "replacements"
    static let unloadMinutesKey = "unloadMinutes"
    static let checkForUpdatesKey = "checkForUpdates"

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            enabledKey: true,
            removeFillersKey: true,
            rewriteLikeKey: false,
            spaceAfterPunctuationKey: true,
            endWithPeriodKey: true,
            playSoundsKey: true,
            microphoneKey: MicrophoneReadiness.onDemand.rawValue,
            unloadMinutesKey: 10,
            checkForUpdatesKey: true,
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

    static var microphone: MicrophoneReadiness {
        defaults.string(forKey: microphoneKey).flatMap(MicrophoneReadiness.init) ?? .onDemand
    }

    static var playSounds: Bool {
        defaults.bool(forKey: playSoundsKey)
    }

    /// Zero keeps the model loaded forever.
    static var unloadMinutes: Int {
        defaults.integer(forKey: unloadMinutesKey)
    }

    static var checkForUpdates: Bool {
        defaults.bool(forKey: checkForUpdatesKey)
    }

    private static func decoded<Value: Decodable>(_ key: String) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Value.self, from: $0) }
    }
}

/// What the panel shows that is not a stored preference.
final class PanelModel: ObservableObject {
    enum UpdateProgress: Equatable {
        case idle
        case installing
        case failed(String)
    }

    @Published var status = ""
    @Published var isProblem = false
    @Published var update: AvailableUpdate?
    @Published var updateProgress = UpdateProgress.idle

    enum ModelProgress: Equatable {
        case idle
        case installing(Double)
        case failed(String)
    }

    @Published var modelUpdate: ModelUpdate?
    @Published var modelProgress = ModelProgress.idle
    /// The pinned revision in use, or nil for the first download.
    @Published var modelRevision = ModelStore.active.revision
}

/// Everything Squawk has to show, in the one panel that drops from the menu
/// bar icon. There is no settings window.
struct PanelView: View {
    @ObservedObject var model: PanelModel
    /// Pauses the global shortcut while a new one is being learned.
    let setLearning: (Bool) -> Void
    /// Records a couple of seconds and returns what the recognizer heard,
    /// without name correction, for training a name.
    let hear: () async -> String?
    let installUpdate: () -> Void
    let installModel: () -> Void

    @AppStorage(Preferences.enabledKey) private var enabled = true
    @AppStorage(Preferences.removeFillersKey) private var removeFillers = true
    @AppStorage(Preferences.rewriteLikeKey) private var rewriteLike = false
    @AppStorage(Preferences.spaceAfterPunctuationKey) private var spaceAfterPunctuation = true
    @AppStorage(Preferences.endWithPeriodKey) private var endWithPeriod = true
    @AppStorage(Preferences.playSoundsKey) private var playSounds = true
    @AppStorage(Preferences.microphoneKey) private var microphone = MicrophoneReadiness.onDemand
    @AppStorage(Preferences.replacementsKey) private var replacements = ""
    @AppStorage(Preferences.unloadMinutesKey) private var unloadMinutes = 10
    @AppStorage(Preferences.checkForUpdatesKey) private var checkForUpdates = true
    @AppStorage("panel.pane") private var pane = Pane.dictation
    @State private var binding = Preferences.binding
    @State private var names = Preferences.names
    @State private var trainingName: UUID?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let update = model.update { updateBanner(update) }
            if let update = model.modelUpdate { modelBanner(update) }
            paneButtons

            switch pane {
            case .dictation: dictationPane
            case .cleanup: cleanupPane
            case .names: namesPane
            case .replacements: replacementsPane
            case .general: generalPane
            }

            HStack {
                Text("Squawk \(Updater.currentVersion?.description ?? "")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: binding) { _, new in Preferences.binding = new }
        .onChange(of: names) { _, new in Preferences.names = new }
    }

    /// One icon per pane across the top; the panel shows one pane at a time.
    private var paneButtons: some View {
        HStack(spacing: 6) {
            ForEach(Pane.allCases) { candidate in
                Button {
                    pane = candidate
                } label: {
                    Image(systemName: candidate.symbol)
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .foregroundStyle(pane == candidate ? Color.accentColor : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.primary.opacity(pane == candidate ? 0.12 : 0.05)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.accentColor.opacity(pane == candidate ? 0.9 : 0), lineWidth: 1.5))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help(candidate.title)
                .accessibilityLabel(candidate.title)
            }
        }
    }

    private func title(_ pane: Pane) -> some View {
        Text(pane.title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }

    @ViewBuilder private var dictationPane: some View {
        title(.dictation)
        Card {
                Row("Dictation key") {
                    ShortcutRecorder(binding: $binding, setLearning: setLearning)
                    Switch(isOn: $enabled)
                }
                Divider()
                Row("Sounds on start and stop") { Switch(isOn: $playSounds) }
                Divider()
                Row("Keep microphone open") {
                    Picker("", selection: $microphone) {
                        ForEach(MicrophoneReadiness.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden().controlSize(.small).fixedSize()
                    .help("Opening the microphone swallows the first word. Keeping it open avoids that; macOS shows its microphone indicator while it is open, and Bluetooth headsets drop to call quality.")
                }
            }
    }

    @ViewBuilder private var cleanupPane: some View {
        title(.cleanup)
        Card {
                    Row("Remove um, uh and stutters") { Switch(isOn: $removeFillers) }
                    Divider()
                    Row("Remove filler \"like\"") { Switch(isOn: $rewriteLike) }
                        .help("Also turns \"she was like\" into \"she said\".")
                    Divider()
                    Row("Space after punctuation") { Switch(isOn: $spaceAfterPunctuation) }
                        .help("Also puts a space between one dictation and the next.")
                    Divider()
                    Row("End with a full stop") { Switch(isOn: $endWithPeriod) }
        }
    }

    @ViewBuilder private var namesPane: some View {
        title(.names)
        Card {
                    ForEach($names) { $entry in
                        HStack(spacing: 6) {
                            TextField("Name", text: $entry.text).frame(width: 80)
                            TextField("Sounds like: terek, tarik", text: $entry.soundsLike)
                            Button(trainingName == entry.id ? "…" : "Train") { train(entry.id) }
                                .disabled(trainingName != nil || entry.name.isEmpty)
                                .help("Click, then say the name. What Squawk hears is added as a sound-alike.")
                            Button {
                                names.removeAll { $0.id == entry.id }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                        }
                        .textFieldStyle(.roundedBorder).controlSize(.small)
                        Divider()
                    }
                    Button("Add name") { names.append(NameEntry()) }.controlSize(.small)
                }
                Text("Squawk re-listens to the audio whenever it hears a name or one of its sound-alikes.")
                    .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var replacementsPane: some View {
        title(.replacements)
                TextEditor(text: $replacements)
                    .font(.callout.monospaced())
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("One per line: spoken => written")
                    .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private var generalPane: some View {
        title(.general)
        Card {
                    Row("Free model memory after") {
                        Picker("", selection: $unloadMinutes) {
                            Text("1 minute idle").tag(1)
                            Text("10 minutes idle").tag(10)
                            Text("1 hour idle").tag(60)
                            Text("Never").tag(0)
                        }
                        .labelsHidden().controlSize(.small).fixedSize()
                    }
                    Divider()
                    Row("Launch at login") { Switch(isOn: $launchAtLogin) }
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                try enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                                loginError = nil
                            } catch {
                                loginError = error.localizedDescription
                            }
                        }
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                    Divider()
                    Row("Check for updates daily") { Switch(isOn: $checkForUpdates) }
                        .help("Asks GitHub for a newer Squawk and Hugging Face for a newer speech model. Nothing about you or this Mac is sent.")
        }
        Text("Speech model: Parakeet TDT 0.6B v3, \(model.modelRevision.map { "revision \($0.prefix(7))" } ?? "as first downloaded")")
            .font(.caption).foregroundStyle(.secondary)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Squawk").font(.headline)
                Text(model.status)
                    .font(.callout)
                    .foregroundStyle(model.isProblem ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func updateBanner(_ update: AvailableUpdate) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Squawk \(update.version.description) is available").font(.callout.weight(.medium))
                    switch model.updateProgress {
                    case .idle:
                        Link("Release notes", destination: update.page).font(.caption)
                    case .installing:
                        Text("Downloading and installing…").font(.caption).foregroundStyle(.secondary)
                    case .failed(let message):
                        Text(message).font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Link("Download it by hand", destination: update.page).font(.caption)
                    }
                }
                Spacer()
                if model.updateProgress == .installing {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Update", action: installUpdate).controlSize(.small)
                }
            }
        }
    }

    /// The speech model updates on its own track: same banner, separate
    /// button, and the app itself is not replaced.
    private func modelBanner(_ update: ModelUpdate) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("A newer speech model is available").font(.callout.weight(.medium))
                    switch model.modelProgress {
                    case .idle:
                        Text(Self.describe(update)).font(.caption).foregroundStyle(.secondary)
                    case .installing(let fraction):
                        Text(fraction < 1 ? "Downloading, \(Int(fraction * 100))%" : "Testing the new model…")
                            .font(.caption).foregroundStyle(.secondary)
                    case .failed(let message):
                        Text(message).font(.caption).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if case .installing(let fraction) = model.modelProgress {
                    ProgressView(value: fraction).progressViewStyle(.circular).controlSize(.small)
                } else {
                    Button("Update", action: installModel).controlSize(.small)
                }
            }
        }
    }

    private static func describe(_ update: ModelUpdate) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(update.bytes), countStyle: .file)
        guard let published = update.published else { return "\(size) download" }
        return "Published \(published.formatted(date: .abbreviated, time: .omitted)), \(size) download"
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

/// A rounded box of rows, the panel's basic unit.
private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) { content }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }
}

/// A label on the left and its control on the right.
private struct Row<Control: View>: View {
    let title: String
    @ViewBuilder let control: Control

    init(_ title: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            control
        }
    }
}

private struct Switch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
}

enum Pane: String, CaseIterable, Identifiable {
    case dictation, cleanup, names, replacements, general

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var symbol: String {
        switch self {
        case .dictation: "mic"
        case .cleanup: "wand.and.stars"
        case .names: "person.text.rectangle"
        case .replacements: "arrow.left.arrow.right"
        case .general: "gearshape"
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
        .focusable(false)
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
