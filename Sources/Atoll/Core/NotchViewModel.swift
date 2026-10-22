import SwiftUI
import Combine

enum NotchState: Equatable {
    case closed
    case open
}

enum NotchTab: String, CaseIterable, Identifiable {
    case home = "Home"
    case shelf = "Shelf"
    case agents = "Agents"
    case scores = "Scores"
    case tools = "Tools"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: return "play.circle"
        case .shelf: return "tray.full"
        case .agents: return "sparkles.rectangle.stack"
        case .scores: return "sportscourt"
        case .tools: return "wrench.and.screwdriver"
        }
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var state: NotchState = .closed
    @Published var tab: NotchTab = .home
    @Published var geometry: NotchGeometry
    @Published var isHoveringClosedNotch = false
    /// Set while a drag-and-drop is hovering anywhere near the notch; forces the shelf open.
    @Published var isDropTargeted = false
    /// Pin/lock: while true the open notch never auto-closes.
    @Published var isPinned = false

    let settings: SettingsStore

    /// Size of the expanded notch content (user-adjustable).
    var openSize: CGSize {
        CGSize(width: max(480, settings.openWidth), height: max(300, settings.openHeight))
    }
    /// Measured widths of the live-activity "wings" flanking the closed notch.
    /// Updated by ClosedNotchView via preference keys.
    @Published var leftWingWidth: CGFloat = 0
    @Published var rightWingWidth: CGFloat = 0

    /// The black body drawn over the hardware cutout: the measured notch plus
    /// the user's calibration (see `SettingsStore.notchExtraWidth`).
    var closedNotchSize: CGSize {
        CGSize(width: max(60, geometry.notchSize.width + settings.notchExtraWidth),
               height: max(12, geometry.notchSize.height + settings.notchExtraHeight))
    }

    var closedSize: CGSize {
        CGSize(width: closedNotchSize.width + leftWingWidth + rightWingWidth,
               height: closedNotchSize.height)
    }

    private var hoverOpenTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?

    var onStateChange: ((NotchState) -> Void)?

    init(geometry: NotchGeometry, settings: SettingsStore) {
        self.geometry = geometry
        self.settings = settings
    }

    // Near-critically damped: the hub settles without the overshoot that read
    // as bounce. Close is a touch quicker than open.
    static let openAnimation = Animation.spring(response: 0.36, dampingFraction: 0.9)
    static let closeAnimation = Animation.spring(response: 0.28, dampingFraction: 0.95)

    func open(tab: NotchTab? = nil) {
        closeTask?.cancel()
        if let tab { self.tab = tab }
        guard state != .open else { return }
        withAnimation(Self.openAnimation) { state = .open }
        onStateChange?(.open)
    }

    func close(after delay: TimeInterval = 0) {
        hoverOpenTask?.cancel()
        closeTask?.cancel()
        guard state != .closed else { return }
        closeTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }
            self.isPinned = false
            withAnimation(Self.closeAnimation) { self.state = .closed }
            self.onStateChange?(.closed)
        }
    }

    func toggle() {
        state == .open ? close() : open()
    }

    func hoverChanged(_ hovering: Bool) {
        isHoveringClosedNotch = hovering
        guard settings.openOnHover else { return }
        if hovering {
            // Never hover-open while the inline HUD is showing (or being dragged) —
            // expanding would tear the volume/brightness capsule out mid-interaction.
            let peek = SneakPeekCoordinator.shared
            guard !peek.visible, !peek.isInteracting else { return }
            hoverOpenTask?.cancel()
            hoverOpenTask = Task { [weak self] in
                guard let self else { return }
                let delay = self.settings.hoverDelay
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
                guard !Task.isCancelled else { return }
                // Re-check: the HUD may have appeared during the hover delay.
                let peek = SneakPeekCoordinator.shared
                guard !peek.visible, !peek.isInteracting else { return }
                if self.settings.hapticFeedback {
                    // One tap as the nook actually opens — not on every
                    // hover-enter, which buzzes when the pointer skims the edge.
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
                }
                self.open()
            }
        } else {
            hoverOpenTask?.cancel()
        }
    }

    /// Called when the pointer leaves the open notch entirely.
    func mouseExitedOpenNotch() {
        guard state == .open, !isDropTargeted, !isPinned else { return }
        close(after: 0.25)
    }

    func cancelPendingClose() {
        closeTask?.cancel()
    }
}
