import SwiftUI
import AppKit

/// Moves the close/minimize/zoom buttons inside the sidebar panel.
/// AppKit repositions the buttons on every relayout (resize, full screen, appearance
/// change), so the position is reapplied on those notifications.
struct TrafficLightsPlacement: NSViewRepresentable {
    /// Distance from the window's top-left corner to the close button's top-left corner.
    var x: CGFloat = 30
    var y: CGFloat = 28

    func makeCoordinator() -> Coordinator { Coordinator(x: x, y: y) }

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: v.window) }
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.x = x; context.coordinator.y = y
        DispatchQueue.main.async { context.coordinator.attach(to: nsView.window) }
    }

    final class Coordinator {
        var x: CGFloat, y: CGFloat
        private weak var window: NSWindow?
        private var observers: [NSObjectProtocol] = []

        init(x: CGFloat, y: CGFloat) { self.x = x; self.y = y }
        deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

        func attach(to window: NSWindow?) {
            guard let window else { return }
            if self.window !== window {
                self.window = window
                observers.forEach { NotificationCenter.default.removeObserver($0) }
                let names: [Notification.Name] = [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                                                  NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                                                  NSWindow.didExitFullScreenNotification, NSWindow.didChangeScreenNotification]
                observers = names.map { name in
                    NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in self?.place() }
                }
                // title bar tall enough for the buttons to move down into the panel
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.fullSizeContentView)
                if window.toolbar == nil {
                    let tb = NSToolbar(identifier: "legroom.chrome")
                    tb.showsBaselineSeparator = false
                    window.toolbar = tb
                }
                window.toolbarStyle = .unified
            }
            place()
            // second pass after AppKit finishes its own layout
            DispatchQueue.main.async { [weak self] in self?.place() }
        }

        func place() {
            guard let window else { return }
            let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            for (i, kind) in kinds.enumerated() {
                guard let b = window.standardWindowButton(kind), let container = b.superview else { continue }
                let size = b.frame.size
                let originX = x + CGFloat(i) * 20
                // container coordinates have their origin at the bottom: convert the distance from the top
                let originY = container.bounds.height - y - size.height
                let frame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
                if b.frame != frame { b.frame = frame }
            }
        }
    }
}
