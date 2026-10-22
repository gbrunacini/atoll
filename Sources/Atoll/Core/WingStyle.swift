import SwiftUI

/// Shared look for closed-notch wings, so the bar reads as one piece rather
/// than a row of unrelated badges. Each wing pads itself with `inset` and
/// renders nothing when idle, so an idle wing costs no space.
enum WingStyle {
    /// Primary label: abbreviations, counts, countdowns.
    static let label = Font.system(size: 11, weight: .semibold).monospacedDigit()
    /// Secondary label: times, titles, status words.
    static let detail = Font.system(size: 11, weight: .medium)

    static let primary = Color.white.opacity(0.88)
    static let secondary = Color.white.opacity(0.55)
    static let muted = Color.white.opacity(0.4)

    /// Horizontal padding each wing applies to itself: neighbours end up
    /// twice this apart, and the outermost sits this far from the corner.
    static let inset: CGFloat = 7

    /// Wings fade in with a slight grow — no pop.
    static let transition: AnyTransition = .opacity.combined(with: .scale(scale: 0.92))
    /// Near-critically damped: the bar resizes without overshoot.
    static let animation = Animation.spring(response: 0.3, dampingFraction: 0.92)
}
