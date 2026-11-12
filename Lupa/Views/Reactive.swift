import SwiftUI

/// Pointer state shared by the reactive effects: local position,
/// presence (0…1, with fade), press.
struct PointerState: Equatable {
    var location: CGPoint? = nil
    var pressed = false
    var inside: Bool { location != nil }
}

/// Card that reacts to the cursor, inspired by react-bits' SpotlightCard / TiltedCard / Magnet:
/// a radial spotlight that follows the pointer, a subtle 3D tilt,
/// a border that lights up near the cursor, a shadow that sinks, a "flare" on click.
/// Constants calibrated from react-bits: presence fades in over 100 ms and
/// out over 320 ms; 240 pt spotlight; 6° maximum tilt; 170/16 springs.
struct CursorReactive: ViewModifier {
    var shape: RoundedRectangle
    var spotlight: Color = .white
    var intensity: Double = 0.30           // maximum spotlight opacity (normal blend: plusLighter blows out on light colors)
    var spotlightSize: CGFloat = 150
    var tilt: Double = 6                   // degrees
    var lift: CGFloat = 1.02               // scale on hover
    var borderGlow: Double = 1.0
    var pressFlare = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pointer = PointerState()
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let p = pointer.location ?? center
        let nx = size.width > 0 ? (p.x - center.x) / center.x : 0      // -1…1
        let ny = size.height > 0 ? (p.y - center.y) / center.y : 0
        let presence: Double = pointer.inside ? 1 : 0
        let flare: Double = pointer.pressed && pressFlare ? 1 : 0
        let radius = spotlightSize * (1 + 0.2 * flare)
        let unit = UnitPoint(x: size.width > 0 ? p.x / size.width : 0.5, y: size.height > 0 ? p.y / size.height : 0.5)

        content
            .background(GeometryReader { g in Color.clear.onAppear { size = g.size }.onChange(of: g.size) { _, s in size = s } })
            // spotlight
            .overlay {
                shape.fill(RadialGradient(colors: [spotlight.opacity(intensity * (1 + 0.7 * flare)), spotlight.opacity(0)],
                                          center: unit, startRadius: 0, endRadius: radius))
                    .opacity(presence)
                    .allowsHitTesting(false)
            }
            // border that lights up near the cursor
            .overlay {
                shape.strokeBorder(RadialGradient(colors: [spotlight.opacity(borderGlow), spotlight.opacity(0)],
                                                  center: unit, startRadius: 0, endRadius: radius * 0.9), lineWidth: 1.5)
                    .opacity(presence)
                    .allowsHitTesting(false)
            }
            .scaleEffect(pointer.pressed ? 0.985 : (pointer.inside ? lift : 1))
            .rotation3DEffect(.degrees(reduceMotion ? 0 : -ny * tilt * presence), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(reduceMotion ? 0 : nx * tilt * presence), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .shadow(color: .black.opacity(pointer.inside ? 0.18 : 0.08), radius: pointer.inside ? 28 : 16, y: pointer.inside ? 16 : 8)
            // the cursor is followed with a near-critical spring; entering is fast, leaving is slow (the light "cools down")
            .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.9), value: pointer.location)
            .animation(pointer.inside ? .spring(response: 0.28, dampingFraction: 0.82) : .spring(response: 0.6, dampingFraction: 0.95), value: pointer.inside)
            .animation(.spring(response: 0.16, dampingFraction: 0.7), value: pointer.pressed)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let loc):
                    pointer.location = loc
                case .ended: pointer.location = nil; pointer.pressed = false
                }
            }
            .simultaneousGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pointer.pressed { pointer.pressed = true } }
                .onEnded { _ in pointer.pressed = false })
    }
}

extension View {
    /// Applies the cursor-reactive behavior over a rounded shape.
    func cursorReactive(corner: CGFloat = Theme.cornerXL, spotlight: Color = .white, intensity: Double = 0.30,
                        tilt: Double = 6, lift: CGFloat = 1.02, borderGlow: Double = 1.0) -> some View {
        modifier(CursorReactive(shape: RoundedRectangle(cornerRadius: corner, style: .continuous),
                                spotlight: spotlight, intensity: intensity, tilt: tilt, lift: lift, borderGlow: borderGlow))
    }
}

/// "Magnet" effect (react-bits' Magnet): the content slides a few points toward
/// the cursor while it's nearby, and springs back.
struct Magnetic: ViewModifier {
    var strength: CGFloat = 8          // maximum offset in pt
    var scale: CGFloat = 1.04
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset: CGSize = .zero
    @State private var inside = false
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in Color.clear.onAppear { size = g.size }.onChange(of: g.size) { _, s in size = s } })
            .scaleEffect(inside ? scale : 1)
            .offset(reduceMotion ? .zero : offset)
            .animation(.spring(response: 0.32, dampingFraction: 0.62), value: offset)
            .animation(.spring(response: 0.32, dampingFraction: 0.7), value: inside)
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    inside = true
                    guard size.width > 0 else { return }
                    let dx = (p.x - size.width / 2) / (size.width / 2)
                    let dy = (p.y - size.height / 2) / (size.height / 2)
                    offset = CGSize(width: dx * strength, height: dy * strength)
                case .ended:
                    inside = false
                    offset = .zero
                }
            }
    }
}

extension View {
    func magnetic(strength: CGFloat = 8, scale: CGFloat = 1.04) -> some View {
        modifier(Magnetic(strength: strength, scale: scale))
    }
}

/// Number that "counts" when its value changes, with rolling digits (CountUp).
struct RollingNumber: View {
    let text: String
    var font: Font = .system(size: 30, weight: .semibold)
    var tracking: CGFloat = 0
    var body: some View {
        Text(text)
            .font(font)
            .tracking(tracking)
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: false))
            .animation(.spring(response: 0.6, dampingFraction: 0.9), value: text)
    }
}

/// Text with a passing shine (ShinyText), for the orb's label.
struct ShinyText: View {
    let text: String
    var font: Font = .system(size: 15, weight: .semibold)
    var speed: Double = 2.4
    @Environment(\.controlActiveState) private var activeState
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: activeState == .inactive)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: speed) / speed
            let x = -0.6 + t * 2.2
            Text(text).font(font)
                .foregroundStyle(.white.opacity(0.85))
                .overlay {
                    Text(text).font(font)
                        .foregroundStyle(LinearGradient(colors: [.clear, .white, .clear],
                                                        startPoint: UnitPoint(x: x - 0.4, y: 0.5),
                                                        endPoint: UnitPoint(x: x + 0.4, y: 0.5)))
                }
        }
    }
}
