// The on-screen proof that Squawk is hearing you: a small pill at the top
// centre of the screen with a live level meter, up only while recording.

import AppKit
import SwiftUI

final class LevelHistory: ObservableObject {
    static let barCount = 28
    @Published private(set) var levels = [CGFloat](repeating: 0, count: barCount)

    /// `rms` is linear amplitude, 0 to 1.
    func push(rms: Float) {
        // Speech sits roughly between -50 and -10 dBFS; map that span to 0...1
        // so a normal voice fills the meter without shouting.
        let decibels = 20 * log10(max(rms, 0.000_01))
        let level = CGFloat(min(max((decibels + 50) / 40, 0), 1))
        levels.removeFirst()
        levels.append(level)
    }

    func reset() {
        levels = [CGFloat](repeating: 0, count: Self.barCount)
    }
}

private struct OverlayView: View {
    @ObservedObject var history: LevelHistory
    private let orange = Color(red: 1.0, green: 0.55, blue: 0.1)

    var body: some View {
        Canvas { context, size in
            let slot = size.width / CGFloat(history.levels.count)
            for (index, level) in history.levels.enumerated() {
                let height = max(3, level * size.height)
                let bar = CGRect(
                    x: CGFloat(index) * slot + slot * 0.2, y: (size.height - height) / 2,
                    width: slot * 0.6, height: height)
                context.fill(Path(roundedRect: bar, cornerRadius: slot * 0.3), with: .color(orange))
            }
        }
        .frame(width: 150, height: 22)
        .shadow(color: orange.opacity(0.9), radius: 4)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(Capsule().fill(Color.black.opacity(0.82)))
        .overlay(Capsule().stroke(orange.opacity(0.55), lineWidth: 1))
        .shadow(color: orange.opacity(0.45), radius: 10)
        // Room for the glow, which would otherwise be clipped by the window.
        .padding(20)
    }
}

final class ListeningOverlay {
    let history = LevelHistory()
    private var panel: NSPanel?

    func show() {
        history.reset()
        let panel = panel ?? makePanel()
        self.panel = panel
        // Under the menu bar of the screen being typed on. visibleFrame already
        // excludes the menu bar, and the menu bar is as tall as the camera
        // notch on notched displays, so this can never sit behind it.
        if let screen = NSScreen.main {
            let size = panel.frame.size
            panel.setFrameOrigin(
                NSPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height + 12))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let content = NSHostingView(rootView: OverlayView(history: history))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = content
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        // Never takes focus or clicks: the text field being dictated into must
        // stay key, and the overlay must not block what is under it.
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return panel
    }
}
