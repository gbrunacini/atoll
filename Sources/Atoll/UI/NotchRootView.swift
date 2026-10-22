import SwiftUI
import UniformTypeIdentifiers

/// Root SwiftUI view hosted in the notch panel. Draws the morphing notch shape
/// and switches between the closed sliver and the open hub.
struct NotchRootView: View {
    @EnvironmentObject var vm: NotchViewModel
    @EnvironmentObject var settings: SettingsStore
    @ObservedObject private var music = MusicManager.shared

    var body: some View {
        VStack(spacing: 0) {
            notch
                .overlay(alignment: .top) { quickPeek }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
    }

    private var notchShape: NotchShape {
        // Square top corners in both states, flush with the bezel like the
        // hardware cutout. The outward flares read as little tabs, especially
        // once a scaled resolution resamples them.
        NotchShape(
            topCornerRadius: 0,
            bottomCornerRadius: vm.state == .open ? settings.openCornerRadius : 13
        )
    }

    private var backgroundFill: AnyShapeStyle {
        // Closed = always pure black: the shape merges with the hardware notch,
        // and any gradient visibly "breaks" across the cutout.
        guard vm.state == .open else { return AnyShapeStyle(Color.black) }
        switch settings.backgroundStyle {
        case "gradient":
            return AnyShapeStyle(LinearGradient(
                colors: [Color(hex: settings.gradientStartHex), Color(hex: settings.gradientEndHex)],
                startPoint: .top, endPoint: .bottom))
        case "artwork":
            return AnyShapeStyle(LinearGradient(
                colors: [music.artworkTint.opacity(0.45), .black],
                startPoint: .top, endPoint: .bottom))
        default:
            return AnyShapeStyle(Color.black)
        }
    }

    /// Keeps the clear cutout pinned over the hardware notch: the container is
    /// centered on the window (= the screen's center line), the wings may be
    /// asymmetric, and an odd-width cutout sits half a point off that line.
    /// Snapped to the pixel grid so edges and text don't land between pixels.
    private var notchOffset: CGFloat {
        let geometry = vm.geometry
        var x = geometry.notchFrame.midX - geometry.screenFrame.midX
        if vm.state == .closed {
            x += (vm.rightWingWidth - vm.leftWingWidth) / 2
        }
        let scale = max(1, geometry.backingScale)
        return (x * scale).rounded() / scale
    }

    private var notch: some View {
        ZStack(alignment: .top) {
            if vm.state == .open {
                OpenNotchView()
                    .frame(width: vm.openSize.width, height: vm.openSize.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            } else {
                ClosedNotchView()
                    .frame(height: vm.closedNotchSize.height)
                    .fixedSize()
                    .transition(.opacity)
            }
        }
        .background(
            notchShape
                .fill(backgroundFill)
                .shadow(color: .black.opacity(vm.state == .open ? 0.6 : 0), radius: 14, y: 6)
        )
        .clipShape(notchShape)
        .overlay {
            // Glow only when open — and always present in the hierarchy with
            // stable identity, faded via opacity. Conditionally INSERTING the
            // stroke would lay it out at the final open bounds instantly while
            // the shape is still morphing (it would have no prior geometry to
            // interpolate from).
            notchShape
                .stroke(settings.accentColor.opacity(0.55), lineWidth: 1)
                .shadow(color: settings.accentColor.opacity(0.5), radius: 5)
                .opacity(settings.showBorderGlow && vm.state == .open ? 1 : 0)
                .allowsHitTesting(false)
        }
        .overlay(
            // Seal the seam against the physical notch.
            Rectangle().fill(.black).frame(height: 1),
            alignment: .top
        )
        .contentShape(notchShape)
        .offset(x: notchOffset)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.leftWingWidth)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: vm.rightWingWidth)
        .onHover { hovering in
            switch vm.state {
            case .closed:
                vm.hoverChanged(hovering)
            case .open:
                if hovering {
                    vm.cancelPendingClose()
                } else {
                    vm.mouseExitedOpenNotch()
                }
            }
        }
        .onTapGesture {
            if vm.state == .closed { vm.open() }
        }
        .contextMenu {
            Button(vm.state == .open ? "Close Nook" : "Open Nook") { vm.toggle() }
            Button("Settings…") {
                NotificationCenter.default.post(name: .atollOpenSettings, object: nil)
            }
            Divider()
            Button("Quit Atoll") { NSApp.terminate(nil) }
        }
        .onDrop(
            of: [.fileURL, .url, .utf8PlainText, .plainText, .data],
            isTargeted: Binding(
                get: { vm.isDropTargeted },
                set: { targeted in
                    vm.isDropTargeted = targeted
                    if targeted, vm.state == .closed {
                        vm.open(tab: .shelf)
                    } else if !targeted, vm.state == .open {
                        // Aborted drag: hover events don't fire during drags, so
                        // schedule a close; an actual drop re-opens and cancels it.
                        vm.close(after: 1.2)
                    }
                }
            )
        ) { providers in
            ShelfStore.shared.ingest(providers)
            vm.open(tab: .shelf)
            return true
        }
        .animation(vm.state == .open ? NotchViewModel.openAnimation : NotchViewModel.closeAnimation, value: vm.state)
    }

    @ViewBuilder
    private var quickPeek: some View {
        if vm.state == .closed, settings.mediaLiveActivity, music.showQuickPeek {
            MediaQuickPeekView()
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.88))
                        .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                )
                .offset(y: vm.closedNotchSize.height + 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: music.showQuickPeek)
        }
    }
}
