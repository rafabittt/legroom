import AppKit
import SwiftUI

/// Command-line arguments for development:
///   --scan <folder>        starts scanning that folder on launch
///   --snapshot <file>      saves a PNG of the app's own window (no screen recording
///                          permission needed, since the window is ours) and quits
///   --delay <seconds>      waits before capturing (default 2 s after the scan ends)
///   --appearance light|dark|system forces the appearance (without saving the preference)
///   --health <0…1>         forces the disk usage fraction (to see the palette)
///   --goal <id>            opens on that tab (map, cleanup, large, apps, clutter)
///   --run                  starts the --goal scan (in the UI nothing runs without the user)
///   --popover memory|cpu|network  opens that Overview card's popover (the capture includes all app windows)
///   --menubar wait        with --snapshot, waits for the menu bar item's popover to be opened
///                          (click the icon; the app can't click its own icon on macOS 26+,
///                          which lives in a system scene) and captures only it, --delay after opening
///   --closewindow <s>      closes the main window after s seconds (tests that the app stays alive)
///
/// Flags WITHOUT a value (--nowait, --run) always go last: AppKit reads the
/// arguments as key/value pairs (NSArgumentDomain) and a lone flag in the middle
/// shifts the following pairs, which prevents the window from being created.
///   --nowait               captures after --delay even with a scan in progress
///   --hover <x,y>          moves the cursor to that point in the window before capturing
///   --verbose              logs each round of readings to stderr, and when they start and stop
enum DebugLaunch {
    static let verbose = CommandLine.arguments.contains("--verbose")
    static func verboseLog(_ s: @autoclosure () -> String) { if verbose { log(s()) } }

    /// Called in the App's init, before any view: registers `--appearance`
    /// in the UserDefaults argument domain, which @AppStorage reads before
    /// the saved value, without overwriting the user's preference.
    static func early() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--appearance"), i + 1 < args.count,
              AppearanceMode(rawValue: args[i + 1]) != nil else { return }
        var domain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        domain[AppearanceMode.key] = args[i + 1]
        UserDefaults.standard.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
    }

    @MainActor static func handle(state: AppState) {
        let args = CommandLine.arguments
        if args.contains("--snapshot") { log("handle: \(args.dropFirst().joined(separator: " "))") }
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let h = value("--health"), let f = Double(h) { state.healthOverride = f }
        let goalFlag = value("--goal").flatMap { Goal(rawValue: $0) }
        state.debugOpenMetric = value("--popover")
        let snapshot = value("--snapshot")
        let delay = Double(value("--delay") ?? "") ?? 2
        let noWait = args.contains("--nowait")
        let hover: CGPoint? = value("--hover").flatMap { v in
            let parts = v.split(separator: ",").compactMap { Double($0) }
            return parts.count == 2 ? CGPoint(x: parts[0], y: parts[1]) : nil
        }
        if let path = value("--scan") {
            let url = URL(fileURLWithPath: path)
            state.select(.folder(url, label: url.lastPathComponent))
            state.startScan()
        }
        if let secs = value("--closewindow").flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + secs) {
                mainWindow?.performClose(nil)
                log("main window closed; app still alive")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { log("3 s later: app still alive (visible windows: \(NSApp.windows.filter(\.isVisible).count))") }
            }
        }
        // --uninstall <app>: opens the uninstall review (moves nothing; only shows it)
        let uninstall = value("--uninstall")
        if let path = uninstall {
            let url = URL(fileURLWithPath: path)
            let node = FileNode(name: path, isDirectory: true, isHidden: false)
            node.allocatedSize = AppLeftovers.allocatedSize(url)
            state.startUninstall([node])
            // --confirm: actually uninstalls through the same path as the button (everything goes to the Trash)
            if args.contains("--confirm") {
                Task { @MainActor in
                    while state.pendingUninstall?.searching == true { try? await Task.sleep(for: .milliseconds(200)) }
                    log("uninstalling: \(state.pendingUninstall?.selected.count ?? 0) leftovers, \(Format.bytes(state.pendingUninstall?.selectedBytes ?? 0))")
                    state.confirmUninstall()
                    try? await Task.sleep(for: .seconds(8))
                    log("notice: \(state.trashNotice ?? "-") | error: \(state.errorMessage ?? "-")")
                    NSApp.terminate(nil)
                }
            }
            Task.detached {
                for l in AppLeftovers.find(for: [url]) { log("leftover: \(l.suggested ? "[x]" : "[ ]") \(l.kind.rawValue) | \(Format.bytes(l.bytes)) | \(l.url.path)") }
            }
        }
        let menubar = value("--menubar")
        // --settings: opens the Settings window (to reproduce problems in it)
        if args.contains("--settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                log("settings opened")
            }
        }
        if let goalFlag {
            log("selecting goal \(goalFlag.rawValue)")
            state.selectGoal(goalFlag)
            log("goal selected")
            // --run: starts the goal's scan (development only; in the UI nothing runs on its own)
            if args.contains("--run") {
                if state.selectedSource == nil { state.refreshVolumes() }
                if goalFlag == .map { state.startScan() } else { state.runGoal(goalFlag) }
            }
        }
        guard let snapshot else { return }
        log("snapshot scheduled: \(snapshot) delay=\(delay) nowait=\(noWait)")
        // window centered on screen, so popovers fit in the capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.windows.first(where: { $0.isVisible && $0.frame.height > 200 })?.center()
        }
        Task { @MainActor in
            // waits for the scan to finish (up to 10 min) and a bit more for the layout to settle
            let deadline = Date().addingTimeInterval(600)
            if !noWait {
                while (state.isScanning || !state.goalScanning.isEmpty || state.restoringMap) && Date() < deadline { try? await Task.sleep(for: .milliseconds(200)) }
            }
            if menubar != nil {
                log("waiting for the menu bar popover to open (click the icon)")
                let limit = Date().addingTimeInterval(120)
                while !(MenuBarPanel.hostWindow?.isVisible ?? false) && Date() < limit { try? await Task.sleep(for: .milliseconds(200)) }
            }
            try? await Task.sleep(for: .seconds(delay))
            if let hover { moveCursor(toWindowPoint: hover); try? await Task.sleep(for: .milliseconds(900)) }
            log("capturing (scanning=\(state.isScanning), error=\(state.errorMessage ?? "-"))")
            if menubar != nil {
                // only the menu bar popover (the icon lives in a system scene and isn't included in the capture)
                capture(windows: [MenuBarPanel.hostWindow].compactMap { $0 }.filter(\.isVisible), to: snapshot)
            } else if uninstall != nil {
                while state.pendingUninstall?.searching == true { try? await Task.sleep(for: .milliseconds(200)) }
                try? await Task.sleep(for: .seconds(1))
                // the SwiftUI sheet isn't included in window captures; render the review directly
                let r = ImageRenderer(content: UninstallSheet(flat: true).environment(state).environment(\.colorScheme, .light).environment(\.controlActiveState, .key))
                r.scale = 2
                if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: snapshot))
                }
                state.pendingUninstall = nil
            } else {
                captureMainWindow(to: snapshot)
            }
            log("quitting")
            let saveDeadline = Date().addingTimeInterval(30)
            while MapStore.isSaving && Date() < saveDeadline { try? await Task.sleep(for: .milliseconds(100)) }
            NSApp.terminate(nil)
            exit(0)
        }
    }

    static func log(_ s: String) { FileHandle.standardError.write(("[legroom] " + s + "\n").data(using: .utf8)!) }

    /// Moves the real cursor (HID event) to a point in the window, measured
    /// from the top-left corner, to capture hover states.
    @MainActor static func moveCursor(toWindowPoint p: CGPoint) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.height > 200 }),
              let screen = window.screen ?? NSScreen.main else { return }
        let f = window.frame
        // CoreGraphics screen coordinates have their origin at the top left
        let global = CGPoint(x: f.minX + p.x, y: screen.frame.maxY - f.maxY + p.y)
        if let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: global, mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
        CGWarpMouseCursorPosition(global)
        if let e = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: global.x + 1, y: global.y), mouseButton: .left) {
            e.post(tap: .cghidEventTap)
        }
        // Besides the HID event, delivers a synthetic mouseMoved straight to the window,
        // so SwiftUI tracking areas react even without accessibility
        // permission.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let local = NSPoint(x: p.x, y: window.contentLayoutRect.height - p.y + (window.frame.height - window.contentLayoutRect.height) * 0)
        for dx in [0.0, 1.0, 2.0] {
            if let ev = NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: local.x + dx, y: local.y), modifierFlags: [],
                                           timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                           context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
                window.sendEvent(ev)
            }
        }
    }

    @MainActor static var mainWindow: NSWindow? {
        NSApp.windows.first { ($0.identifier?.rawValue ?? "").hasPrefix(LegroomApp.mainWindowID) && $0.isVisible }
    }

    @MainActor static func captureMainWindow(to path: String) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.frame.height > 200 }) else { return }
        // all of the app's visible windows (including popovers), except the menu bar icon
        let visible = NSApp.windows.filter { $0.isVisible && $0.alphaValue > 0 && $0 !== MenuBarPanel.hostWindow
            && !String(describing: type(of: $0)).contains("StatusBar") }
        capture(windows: visible, around: window, to: path)
    }

    /// Captures these windows of the app itself, cropped to the union of their frames.
    @MainActor static func capture(windows visible: [NSWindow], around base: NSWindow? = nil, to path: String) {
        // the menu bar icon (NSStatusItemScene, macOS 26+) has a window number outside the CGWindowID range
        let visible = visible.filter { $0.windowNumber > 0 && $0.windowNumber <= Int(UInt32.max) }
        guard let window = base ?? visible.first else { log("nothing to capture"); return }
        let ids = visible.map { CGWindowID($0.windowNumber) } as [CGWindowID]
        let union = visible.reduce(window.frame) { $0.union($1.frame) }
        guard let screen = NSScreen.screens.first ?? window.screen else { return }
        // CoreGraphics uses an origin at the top of the main screen
        let cgBounds = CGRect(x: union.minX, y: screen.frame.maxY - union.maxY, width: union.width, height: union.height)
        // CoreGraphics expects the IDs stored directly as pointers in the CFArray
        var ptrs: [UnsafeRawPointer?] = ids.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let array = CFArrayCreate(nil, &ptrs, ptrs.count, nil),
              let cg = CGImage(windowListFromArrayScreenBounds: cgBounds, windowArray: array, imageOption: [.boundsIgnoreFraming, .bestResolution]) else {
            log("capture failed (\(ids.count) windows)"); return
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

