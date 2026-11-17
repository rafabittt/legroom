import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// Locks the keyboard so it can be wiped clean: every key press (letters,
/// modifiers, function row, media and brightness keys) is swallowed by an
/// event tap until you click Unlock in the floating panel, or after
/// `duration` as a safety net. The mouse and trackpad keep working, and the
/// tap disappears with the app if it quits.
///
/// Blocking keys needs the Accessibility permission (System Settings ›
/// Privacy & Security › Accessibility); Legroom asks for it the first time.
/// The power / Touch ID button can't be blocked by any app.
@MainActor @Observable
final class KeyboardLock {
    static let shared = KeyboardLock()
    static let duration: TimeInterval = 180

    private(set) var isLocked = false
    /// Seconds left before it unlocks on its own.
    private(set) var remaining: Int = 0
    /// Keys swallowed during this lock (shown in the panel, so you can see it working).
    private(set) var blocked = 0

    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var deadline = Date()
    @ObservationIgnored private var panel: NSPanel?

    private init() {}

    func toggle() { isLocked ? unlock() : lock() }

    func lock() {
        guard !isLocked else { return }
        guard Self.hasPermission(prompt: false) else { askForPermission(); return }

        // keyDown, keyUp, flagsChanged and NX_SYSDEFINED (media / brightness keys)
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue) | (1 << 14)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: keyboardLockCallback, userInfo: nil) else {
            Trail.note("keyboard lock: tapCreate failed (permission?)")
            askForPermission()
            return
        }
        KeyboardLockTap.port = tap
        KeyboardLockTap.onBlocked = { [weak self] in self?.blocked += 1 }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = src

        blocked = 0
        deadline = Date().addingTimeInterval(Self.duration)
        remaining = Int(Self.duration)
        isLocked = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.remaining = max(0, Int(self.deadline.timeIntervalSinceNow.rounded(.up)))
                if self.remaining == 0 { self.unlock() }
            }
        }
        showPanel()
        Trail.note("keyboard lock: on")
    }

    func unlock() {
        guard isLocked else { return }
        timer?.invalidate(); timer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        KeyboardLockTap.port = nil
        KeyboardLockTap.onBlocked = nil
        isLocked = false
        panel?.orderOut(nil); panel = nil
        Trail.note("keyboard lock: off (\(blocked) keys blocked)")
    }

    /// Adds one more minute (the panel's "+1 min").
    func extend() {
        deadline = deadline.addingTimeInterval(60)
        remaining = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
    }

    // MARK: Permission

    static func hasPermission(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    private func askForPermission() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Allow Legroom to lock the keyboard")
        alert.informativeText = String(localized: "To ignore key presses while you clean, macOS needs you to turn on Legroom in System Settings › Privacy & Security › Accessibility. Legroom only uses it while the keyboard is locked. Then click Lock Keyboard again.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Adds Legroom to the list (switched off) so the person only has to flip it on.
        _ = Self.hasPermission(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Panel

    private func showPanel() {
        let host = NSHostingView(rootView: KeyboardLockPanel().environment(self))
        host.sizingOptions = [.preferredContentSize]
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 300),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.setContentSize(host.fittingSize)
        if let screen = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: screen.midX - p.frame.width / 2, y: screen.midY - p.frame.height / 2))
        }
        p.orderFrontRegardless()
        panel = p
    }
}

/// The C callback can't capture context; it reaches the tap through here.
enum KeyboardLockTap {
    nonisolated(unsafe) static var port: CFMachPort?
    nonisolated(unsafe) static var onBlocked: (@MainActor () -> Void)?
}

private func keyboardLockCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                  userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        // macOS switches a slow tap off; switch it straight back on while locked
        if let port = KeyboardLockTap.port { CGEvent.tapEnable(tap: port, enable: true) }
        return Unmanaged.passUnretained(event)
    case .keyDown, .flagsChanged:
        if let f = KeyboardLockTap.onBlocked { MainActor.assumeIsolated { f() } }
        return nil
    case .keyUp:
        return nil
    default:
        // NX_SYSDEFINED: only swallow the media / brightness keys (subtype 8),
        // not the other system-defined events (some of them carry mouse buttons).
        if type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.subtype.rawValue == 8 {
            if (ns.data1 & 0xFF00) >> 8 == 0x0A, let f = KeyboardLockTap.onBlocked { MainActor.assumeIsolated { f() } }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}

/// The floating panel shown while the keyboard is locked. It's the way back:
/// the mouse still works, so one click on Unlock ends it.
struct KeyboardLockPanel: View {
    @Environment(KeyboardLock.self) private var lock
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "keyboard")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.muted)
                .padding(.top, 6)
            VStack(spacing: 5) {
                Text("Keyboard locked").font(.system(size: 17, weight: .semibold))
                Text("Clean away: key presses do nothing until you unlock. The mouse and trackpad still work.")
                    .font(.system(size: 12.5)).foregroundStyle(.muted)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                Text("Unlocks by itself in \(Self.clock(lock.remaining))")
                    .monospacedDigit()
                Button("+1 min") { lock.extend() }
                    .buttonStyle(.borderless).font(.system(size: 11.5, weight: .semibold))
            }
            .font(.system(size: 11.5)).foregroundStyle(.faint)
            if lock.blocked > 0 {
                Text("\(lock.blocked) key presses ignored")
                    .font(.system(size: 11.5)).foregroundStyle(.faint).monospacedDigit()
                    .contentTransition(.numericText())
            }
            PillButton(title: String(localized: "Unlock Keyboard"), systemImage: "lock.open") { lock.unlock() }
                .padding(.top, 2)
        }
        .padding(24)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        .padding(10)
        .animation(.snappy, value: lock.blocked)
    }

    static func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }
}

/// The button that turns it on (Overview header and the menu bar panel).
/// `iconOnly` is the round version for the narrow menu bar panel.
struct KeyboardLockButton: View {
    var iconOnly = false
    private var lock: KeyboardLock { KeyboardLock.shared }
    var body: some View {
        Group {
            if iconOnly {
                RoundIconButton(systemImage: lock.isLocked ? "lock.open" : "keyboard") { lock.toggle() }
                    .accessibilityLabel(lock.isLocked ? Text("Unlock Keyboard") : Text("Lock Keyboard"))
            } else {
                PillButton(title: lock.isLocked ? String(localized: "Unlock Keyboard") : String(localized: "Lock Keyboard"),
                           systemImage: lock.isLocked ? "lock.open" : "keyboard",
                           prominent: false, compact: true) { lock.toggle() }
            }
        }
        .help(Text("Ignores every key press so you can clean the keyboard. Click Unlock (or wait 3 minutes) to end it."))
    }
}
