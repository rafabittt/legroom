import SwiftUI

/// "Hold to confirm" button (react-bits HoldButton, translated to SwiftUI
/// with Apple's fluidity principles): responds on press, fills
/// linearly while the pointer stays on it, springs back if released early,
/// and only then runs. It's the only trigger for the full disk scan.
struct HoldButton: View {
    let title: String
    var holdingTitle = String(localized: "Keep holding…")
    var doneTitle = String(localized: "Scanning disk")
    var systemImage: String? = "magnifyingglass"
    var holdTime: Double = 1.1
    var fill: Color
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = 0
    @State private var holding = false
    @State private var done = false
    @State private var size: CGSize = .zero
    @State private var holdTask: Task<Void, Never>?
    @State private var pressedAt: Date?
    @State private var hover = false

    var body: some View {
        let dark = scheme == .dark
        let base = dark ? Color.white : Color.black
        let baseText = dark ? Color.black : Color.white
        let shape = Capsule()

        ZStack {
            shape.fill(base)
            // same hover as the main buttons on the other screens (PillButton)
            shape.fill(Color.white.opacity(hover && !dark && !holding && !done ? 0.12 : 0))
            label(color: baseText)
            // fill with a wavy crest (or a fade, with Reduce Motion)
            TimelineView(.animation(minimumInterval: 1 / 60, paused: !holding || reduceMotion)) { ctx in
                let phase = ctx.date.timeIntervalSinceReferenceDate * 6
                ZStack {
                    shape.fill(fill)
                    label(color: .white)
                }
                .mask {
                    if reduceMotion {
                        Rectangle().opacity(progress)
                    } else {
                        WaveFill(progress: progress, amplitude: 5, phase: phase)
                    }
                }
            }
            .allowsHitTesting(false)
            // pulse on completion
            shape.strokeBorder(fill.opacity(done ? 0 : 0.6), lineWidth: 2)
                .scaleEffect(done ? 1.18 : 1)
                .opacity(done ? 0 : 0)
                .animation(.easeOut(duration: 0.6), value: done)
        }
        .frame(height: 52)
        .background(GeometryReader { g in Color.clear.onAppear { size = g.size }.onChange(of: g.size) { _, s in size = s } })
        .clipShape(shape)
        .shadow(color: .black.opacity(hover && !holding && !done ? (dark ? 0.4 : 0.12) : 0), radius: 10, y: 5)
        .shadow(color: fill.opacity(holding || done ? 0.35 : 0), radius: 18, y: 8)
        .scaleEffect(holding ? 0.97 : (hover && !done && !reduceMotion ? 1.03 : 1))
        .onHover { h in withAnimation(h ? .spring(response: 0.25, dampingFraction: 0.9) : .spring(response: 0.5, dampingFraction: 1.0)) { hover = h } }
        .contentShape(shape)
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in
                if !holding && !done { begin() }
                // release when dragging outside (10 pt of slack)
                let r = CGRect(origin: .zero, size: size).insetBy(dx: -10, dy: -10)
                if holding && !r.contains(v.location) { release() }
            }
            .onEnded { _ in release() })
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space, phases: [.down, .up]) { press in
            if press.phase == .down { if !holding && !done { begin() } } else { release() }
            return .handled
        }
        .onKeyPress(.return, phases: [.down, .up]) { press in
            if press.phase == .down { if !holding && !done { begin() } } else { release() }
            return .handled
        }
        .animation(.spring(response: 0.3, dampingFraction: 1.0), value: holding)
        .accessibilityLabel(title)
        .accessibilityHint("Hold for \(holdTime.formatted(.number.precision(.fractionLength(1)))) seconds to start.")
        .help("Hold to start. Releasing early cancels.")
    }

    @ViewBuilder private func label(color: Color) -> some View {
        HStack(spacing: 8) {
            if done {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
            } else if let systemImage {
                Image(systemName: systemImage).font(.system(size: 13, weight: .semibold))
            }
            Text(done ? doneTitle : (holding ? holdingTitle : title))
                .font(.system(size: 14, weight: .semibold)).lineLimit(1).fixedSize()
                .contentTransition(.opacity)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 22)
        .animation(.easeOut(duration: 0.18), value: holding)
        .animation(.easeOut(duration: 0.18), value: done)
    }

    private func begin() {
        holding = true
        pressedAt = Date()
        withAnimation(.linear(duration: holdTime)) { progress = 1 }
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(holdTime))
            guard !Task.isCancelled, holding else { return }
            complete()
        }
    }

    private func release() {
        guard holding else { return }
        holding = false
        holdTask?.cancel()
        holdTask = nil
        // snaps back quickly, with the refs' exit curve (0.23 / 1 / 0.32 / 1)
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.22)) { progress = 0 }
    }

    private func complete() {
        holding = false
        done = true
        progress = 1
        action()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            withAnimation(.easeOut(duration: 0.25)) { progress = 0; done = false }
        }
    }
}

/// Rectangle that grows from the left with a wavy right edge.
struct WaveFill: Shape {
    var progress: Double
    var amplitude: CGFloat
    var phase: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard progress > 0 else { return p }
        let x = (rect.width + amplitude * 2) * progress - amplitude
        p.move(to: CGPoint(x: 0, y: 0))
        let steps = 24
        for i in 0...steps {
            let y = rect.height * CGFloat(i) / CGFloat(steps)
            let wave = sin((Double(y) / Double(rect.height)) * .pi * 2 * 1.5 + phase) * Double(amplitude) * progress * (1 - progress) * 4
            p.addLine(to: CGPoint(x: x + CGFloat(wave), y: y))
        }
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}
