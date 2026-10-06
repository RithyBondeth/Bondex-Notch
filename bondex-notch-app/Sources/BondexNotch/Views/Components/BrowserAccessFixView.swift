import SwiftUI

/// What the Music tab shows when a browser is hiding what is playing: why, in
/// plain words, and a button that fixes it.
///
/// For a first-time user this is the whole setup. Before it, the same state
/// was a paragraph of menu paths — and for Dia, a Terminal command that did
/// nothing while Dia was still open — which is a reliable way to make someone
/// conclude the app does not work with YouTube.
struct BrowserAccessFixView: View {
    @ObservedObject var nowPlaying: NowPlayingService
    let browser: MediaApp
    let accent: Color

    private enum Phase: Equatable {
        case idle
        /// Reopening quits the browser, so it asks first.
        case confirming
        case working
        case failed(String)
    }

    @State private var phase: Phase = .idle

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Theme.tertiaryText)
            Text(title)
                .font(.system(size: Theme.TextSize.title, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
            Text(browser.javaScriptHint)
                .font(.system(size: Theme.TextSize.footnote))
                .foregroundStyle(Theme.tertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
            controls
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .animation(Motion.hover, value: phase)
    }

    private var title: String {
        switch browser.mediaAccessFix {
        case .relaunch: return "Let \(browser.displayName) share what’s playing"
        default: return "Allow \(browser.displayName) to share what’s playing"
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch browser.mediaAccessFix {
        case .relaunch:
            relaunchControls
        case .browserSetting:
            PillButton(title: "Open \(browser.displayName)", systemImage: "arrow.up.forward.app", tint: accent, isProminent: true) {
                BrowserMediaSetup.bringToFront(browser)
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private var relaunchControls: some View {
        switch phase {
        case .idle:
            PillButton(title: "Reopen \(browser.displayName)", systemImage: "arrow.clockwise", tint: accent, isProminent: true) {
                phase = .confirming
            }
        case .confirming:
            VStack(spacing: 6) {
                Text("\(browser.displayName) will quit and open again. It normally brings your tabs back.")
                    .font(.system(size: Theme.TextSize.footnote, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                HStack(spacing: 6) {
                    PillButton(title: "Reopen now", systemImage: nil, tint: accent, isProminent: true) {
                        reopen()
                    }
                    PillButton(title: "Not now", systemImage: nil, tint: accent) {
                        phase = .idle
                    }
                }
            }
        case .working:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Reopening \(browser.displayName)…")
                    .font(.system(size: Theme.TextSize.body, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
        case let .failed(message):
            VStack(spacing: 6) {
                Text(message)
                    .font(.system(size: Theme.TextSize.footnote, weight: .medium))
                    .foregroundStyle(Color(red: 0.99, green: 0.72, blue: 0.25))
                    .multilineTextAlignment(.center)
                PillButton(title: "Try again", systemImage: "arrow.clockwise", tint: accent) {
                    reopen()
                }
            }
        }
    }

    private func reopen() {
        phase = .working
        Task {
            switch await nowPlaying.fixBlockedBrowser() {
            case .done:
                phase = .idle
            case .didNotQuit:
                phase = .failed("\(browser.displayName) didn’t quit — it may be asking about open tabs. Answer it, then try again.")
            case .couldNotOpen:
                phase = .failed("Couldn’t reopen \(browser.displayName). Open it from Applications, then try again.")
            }
        }
    }
}

/// A text button in the panel's style: a capsule, filled when it is the
/// thing to press.
struct PillButton: View {
    let title: String
    let systemImage: String?
    let tint: Color
    var isProminent = false
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 10, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: Theme.TextSize.body, weight: .semibold))
            }
            .foregroundStyle(isProminent ? Color.black : Theme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(
                    isProminent
                        ? AnyShapeStyle(tint.opacity(isHovering ? 0.9 : 1))
                        : AnyShapeStyle(Color.white.opacity(isHovering ? 0.15 : 0.08))
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isFocused ? Color.white.opacity(0.9) : Color.white.opacity(0.08),
                    lineWidth: isFocused ? 2 : 0.7
                )
            )
            .contentShape(Capsule())
            .animation(Motion.hover, value: isHovering)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .fixedSize()
    }
}
