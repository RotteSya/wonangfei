import SwiftUI
import UIKit

// MARK: - Gold shimmer

/// Sweeps a gold glint across the modified view every `period` seconds.
/// The clock only runs while `isActive` is true (pass the page's visibility
/// so hidden pager pages don't burn frames) and respects Reduce Motion by
/// freezing the sweep entirely.
struct GoldShimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var period: Double = 5.2
    var intensity: Double = 0.42
    var isActive: Bool = true

    private var animates: Bool { isActive && !reduceMotion }

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animates)) { context in
            let t = animates ? context.date.timeIntervalSinceReferenceDate : 0
            content
                .visualEffect { view, proxy in
                    view.colorEffect(
                        ShaderLibrary.wnfGoldShimmer(
                            .float2(proxy.size),
                            .float(t.truncatingRemainder(dividingBy: 3600)),
                            .float(period),
                            .float(intensity)
                        )
                    )
                }
        }
    }
}

extension View {
    func goldShimmer(period: Double = 5.2, intensity: Double = 0.42, isActive: Bool = true) -> some View {
        modifier(GoldShimmer(period: period, intensity: intensity, isActive: isActive))
    }

    /// Static printed-paper grain. Costs one shader pass only when the view
    /// re-renders, so it is safe on large card fills.
    func paperGrain(_ intensity: Double = 0.035) -> some View {
        visualEffect { view, _ in
            view.colorEffect(ShaderLibrary.wnfPaperGrain(.float(intensity)))
        }
    }
}

// MARK: - Jelly drag (squash & stretch)

/// Soft-body feel for the pager drag, built from classic animation physics
/// instead of a layer shader: the page leans into the travel direction and
/// compresses slightly along it (squash & stretch), so a flick reads as
/// pushing a slab of pudding. Driving `stretch` back to zero through a
/// low-damping spring produces the arrival wobble.
///
/// Deliberately NOT a `distortionEffect`: shader layer effects can't
/// rasterize the AVPlayerLayer hosting the home mascot, and on iOS 26
/// `maxSampleOffset` displaces the rendered layer. Plain transforms compose
/// with everything, cost nothing at rest, and read just as soft in motion.
struct JellyStretch: ViewModifier, Animatable {
    var stretch: CGFloat

    var animatableData: CGFloat {
        get { stretch }
        set { stretch = newValue }
    }

    static let maxStretch: CGFloat = 30

    func body(content: Content) -> some View {
        let normalized = stretch / Self.maxStretch
        return content
            .rotationEffect(.degrees(Double(normalized) * 1.3), anchor: .bottom)
            .scaleEffect(
                x: 1 - abs(normalized) * 0.045,
                y: 1 + abs(normalized) * 0.022,
                anchor: .center
            )
    }
}

extension View {
    func jellyStretch(_ stretch: CGFloat) -> some View {
        modifier(JellyStretch(stretch: stretch))
    }
}

// MARK: - Squish button style

/// The app-wide press feel: a quick pudding squish with a touch of dim, so
/// every tappable surface answers the finger immediately.
struct SquishButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.93

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.025 : 0)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SquishButtonStyle {
    static var squish: SquishButtonStyle { SquishButtonStyle() }
    static func squish(_ scale: CGFloat) -> SquishButtonStyle { SquishButtonStyle(scale: scale) }
}

// MARK: - Haptics

/// Centralized feedback generators so call sites stay one-liners and the
/// generators get reused instead of re-allocated per event.
enum WNFHaptics {
    private static let selectionGenerator = UISelectionFeedbackGenerator()
    private static let softGenerator = UIImpactFeedbackGenerator(style: .soft)
    private static let rigidGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private static let mediumGenerator = UIImpactFeedbackGenerator(style: .medium)
    private static let notificationGenerator = UINotificationFeedbackGenerator()

    static func selection() {
        selectionGenerator.selectionChanged()
    }

    static func soft(intensity: CGFloat = 0.8) {
        softGenerator.impactOccurred(intensity: intensity)
    }

    static func rigid(intensity: CGFloat = 0.9) {
        rigidGenerator.impactOccurred(intensity: intensity)
    }

    static func medium(intensity: CGFloat = 1.0) {
        mediumGenerator.impactOccurred(intensity: intensity)
    }

    static func success() {
        notificationGenerator.notificationOccurred(.success)
    }
}
