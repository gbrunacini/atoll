import SwiftUI

/// Shared type scale, radii and fills for the open hub, so panes that were
/// built separately read as one app. The closed bar has its own `WingStyle`.
enum HubStyle {
    // MARK: Type scale — four sizes, nothing in between.

    /// Pane header ("Scores", "To-dos") and card titles.
    static let title = Font.system(size: 13, weight: .semibold)
    /// Primary row text.
    static let body = Font.system(size: 12.5)
    static let bodyMedium = Font.system(size: 12.5, weight: .medium)
    static let bodyEmphasis = Font.system(size: 12.5, weight: .semibold)
    /// Secondary text: times, counts, metadata.
    static let caption = Font.system(size: 11)
    /// Uppercase section labels; pair with `sectionTracking`.
    static let section = Font.system(size: 9.5, weight: .semibold)
    static let sectionTracking: CGFloat = 0.6
    /// Empty states: a light glyph over a medium-weight line.
    static let emptyGlyph = Font.system(size: 24, weight: .light)
    static let emptyTitle = Font.system(size: 12.5, weight: .medium)

    // MARK: Text on the black hub.

    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.35)

    // MARK: Radii — three roles.

    /// Column and card containers: media card, calendar column, shelf tray.
    static let cardRadius: CGFloat = 12
    /// Rows, cells, thumbnails, text fields.
    static let rowRadius: CGFloat = 8
    /// Small controls: tabs, rail buttons, chips.
    static let controlRadius: CGFloat = 7

    // MARK: Fills.

    static let cardFill = Color.white.opacity(0.05)
    static let hoverFill = Color.white.opacity(0.06)
    static let selectionFill = Color.white.opacity(0.16)
}
