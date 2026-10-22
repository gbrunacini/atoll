import SwiftUI

/// Compact closed-notch wing: a checklist glyph plus the number of open
/// to-dos. Renders nothing when every to-do is completed or the list is
/// empty, so the integrator can compose it unconditionally.
struct TodoCountWing: View {
    @ObservedObject private var store = TodosStore.shared

    var body: some View {
        if store.openCount > 0 {
            HStack(spacing: 3) {
                Image(systemName: "checklist")
                    .font(.system(size: 9, weight: .semibold))
                Text("\(store.openCount)")
                    .font(WingStyle.label)
                    .contentTransition(.numericText())
            }
            .foregroundStyle(WingStyle.primary)
            .padding(.horizontal, WingStyle.inset)
            .frame(maxHeight: .infinity)
            .transition(WingStyle.transition)
            .animation(WingStyle.animation, value: store.openCount)
        }
    }
}
