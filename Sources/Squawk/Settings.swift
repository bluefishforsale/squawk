// The whole settings surface. Anything that would need a second pane does not
// belong in this app.

import ServiceManagement
import SquawkCore
import SwiftUI

enum Preferences {
    static let hotkeyKey = "hotkey"
    static let removeFillersKey = "removeFillers"
    static let replacementsKey = "replacements"
    static let unloadMinutesKey = "unloadMinutes"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            hotkeyKey: Hotkey.rightOption.rawValue,
            removeFillersKey: true,
            unloadMinutesKey: 10,
        ])
    }

    static var hotkey: Hotkey {
        UserDefaults.standard.string(forKey: hotkeyKey).flatMap(Hotkey.init) ?? .rightOption
    }

    static var cleanup: TextCleanup {
        TextCleanup(
            removeFillers: UserDefaults.standard.bool(forKey: removeFillersKey),
            replacements: Replacement.parse(UserDefaults.standard.string(forKey: replacementsKey) ?? ""))
    }

    /// Zero keeps the model loaded forever.
    static var unloadMinutes: Int {
        UserDefaults.standard.integer(forKey: unloadMinutesKey)
    }
}

struct SettingsView: View {
    @AppStorage(Preferences.hotkeyKey) private var hotkey = Hotkey.rightOption
    @AppStorage(Preferences.removeFillersKey) private var removeFillers = true
    @AppStorage(Preferences.replacementsKey) private var replacements = ""
    @AppStorage(Preferences.unloadMinutesKey) private var unloadMinutes = 10
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Picker("Dictation key", selection: $hotkey) {
                ForEach(Hotkey.allCases) { Text($0.label).tag($0) }
            }
            Text("Hold to dictate. Double-tap to lock hands-free, tap again to stop.")
                .font(.footnote).foregroundStyle(.secondary)

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

            Toggle("Remove um and uh", isOn: $removeFillers)

            Section("Replacements, one per line: spoken => written") {
                TextEditor(text: $replacements)
                    .font(.body.monospaced())
                    .frame(height: 90)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
