import SwiftUI
import UniformTypeIdentifiers

/// Root of the panel. Draws the silhouette at the size the current state calls
/// for and swaps the content inside it.
struct NotchRootView: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var notch: NotchViewModel
    @ObservedObject private var settings: SettingsStore

    /// `ImageRenderer` cannot rasterise `.onDrop`, and substitutes a yellow
    /// placeholder for the whole subtree. The offscreen preview tool sets this
    /// to drop the modifier; it is always false in the running app.
    private let isRenderingOffscreen: Bool

    init(environment: AppEnvironment, isRenderingOffscreen: Bool = false) {
        self.environment = environment
        self.notch = environment.notch
        self.settings = environment.settings
        self.isRenderingOffscreen = isRenderingOffscreen
    }

    private var accent: Color { settings.effectiveAccent.color }
    private var geometry: NotchGeometry { notch.geometry }
    private var contentSize: CGSize { geometry.contentSize(for: notch.state) }

    private var bottomRadius: CGFloat {
        notch.state == .collapsed ? Theme.collapsedBottomRadius : Theme.bottomRadius
    }

    /// On a real notch the collapsed panel must be invisible — the hardware is
    /// already black, and drawing fillets there would show two dark tabs
    /// sticking into the menu bar.
    private var silhouetteOpacity: Double {
        (notch.state == .collapsed && geometry.hasHardwareNotch) ? 0 : 1
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                silhouette
                content
                    .frame(width: contentSize.width, height: contentSize.height)
                    .clipped()
            }
            .frame(width: contentSize.width, height: contentSize.height)
            .contentShape(Rectangle())
            .onTapGesture { notch.toggle() }
            .modifier(ShelfDropModifier(environment: environment, isDisabled: isRenderingOffscreen))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.panel(settings.motion), value: notch.state)
    }

    // MARK: Silhouette

    private var silhouette: some View {
        NotchShape(flareRadius: Theme.flareRadius, bottomRadius: bottomRadius)
            // The fillets are drawn outside the body, so the shape needs to be
            // wider than the content by one flare on each side.
            .frame(width: contentSize.width + Theme.flareRadius * 2, height: contentSize.height)
            .foregroundStyle(Theme.surface)
            .overlay(
                NotchShape(flareRadius: Theme.flareRadius, bottomRadius: bottomRadius)
                    .stroke(
                        notch.isDropTargeted ? accent.opacity(0.9) : Color.white.opacity(0.07),
                        lineWidth: notch.isDropTargeted ? 1.6 : 1
                    )
                    .frame(
                        width: contentSize.width + Theme.flareRadius * 2,
                        height: contentSize.height
                    )
            )
            .shadow(color: .black.opacity(notch.state.isExpanded ? 0.45 : 0), radius: 18, y: 8)
            .opacity(silhouetteOpacity)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch notch.state {
        case .collapsed:
            Color.clear
        case .peek:
            PeekView(environment: environment)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        case .expanded:
            ExpandedView(environment: environment)
                .transition(.opacity.combined(with: .offset(y: -8)))
        }
    }
}

private struct ShelfDropModifier: ViewModifier {
    let environment: AppEnvironment
    let isDisabled: Bool

    func body(content: Content) -> some View {
        if isDisabled {
            content
        } else {
            content.onDrop(
                of: [.fileURL],
                delegate: ShelfDropDelegate(environment: environment)
            )
        }
    }
}

/// Drop handling for the shelf, at the panel level so a drag anywhere over the
/// notch opens it.
private struct ShelfDropDelegate: DropDelegate {

    let environment: AppEnvironment

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated { environment.notch.dragEntered() }
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated { environment.notch.dragExited() }
    }

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }

        return MainActor.assumeIsolated {
            environment.notch.isDropTargeted = false

            guard environment.settings.isUnlocked(.shelf),
                  environment.settings.preferences.shelfEnabled else {
                environment.events.post(NotchEvent(
                    kind: .shelf,
                    title: "Drop Shelf is a Pro feature",
                    subtitle: "Add a license key in Settings"
                ))
                return false
            }

            Task { @MainActor in
                let urls = await environment.shelf.resolve(providers: providers)
                guard !urls.isEmpty else { return }
                environment.shelf.add(urls: urls)
                environment.notch.tab = .shelf
                environment.notch.expand()
                environment.notch.setPinned(true)
            }
            return true
        }
    }
}
