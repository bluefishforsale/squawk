// Draws the panel into PNG files without putting anything on screen, for the
// README. Rendering from the real view keeps the screenshots honest: they
// cannot drift from the app the way hand-made captures do.

import AppKit
import SquawkCore
import SwiftUI

enum PaneRenderer {
    static func render(into folder: URL) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // Run from the repository root, there is no bundle to take the icon from.
        if let icon = NSImage(contentsOfFile: "packaging/Squawk.icns") {
            app.applicationIconImage = icon
        }
        // NOTE: switches draw grey here. They only take the accent colour in
        // the key window of the active app, and an offscreen window in a
        // command line run is neither; making it so would steal focus.
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let model = PanelModel()
        model.status = "Hold \(Preferences.binding.keycaps.joined(separator: " + ")) to dictate"
        for pane in Pane.allCases {
            write(pane.rawValue, pane: pane, model: model, to: folder)
        }

        // The panel as it looks when both kinds of update are waiting.
        if let version = AppVersion("1.2.0"), let page = URL(string: "https://github.com/bluefishforsale/squawk/releases") {
            model.update = AvailableUpdate(version: version, dmg: page, page: page)
        }
        model.modelUpdate = ModelUpdate(
            revision: String(repeating: "0", count: 40), published: Date(timeIntervalSince1970: 1_787_000_000),
            bytes: 483_257_242)
        write("updates", pane: .dictation, model: model, to: folder)
    }

    private static func write(_ name: String, pane: Pane, model: PanelModel, to folder: URL) {
        UserDefaults.standard.set(pane.rawValue, forKey: "panel.pane")
        let view = PanelView(model: model, setLearning: { _ in }, hear: { nil }, installUpdate: {}, installModel: {})
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
            .padding(1)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Controls finish drawing on the next turn of the run loop.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: folder.appendingPathComponent("\(name).png"))
    }
}
