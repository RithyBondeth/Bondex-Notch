import AppKit
import SwiftUI

struct ClipboardWidget: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var service: ClipboardHistoryService
    @ObservedObject private var settings: SettingsStore
    @State private var query = ""
    @Environment(\.isRenderingOffscreen) private var isRenderingOffscreen

    init(environment: AppEnvironment) {
        self.environment = environment
        self.service = environment.clipboard
        self.settings = environment.settings
    }

    private var accent: Color { settings.effectiveAccentColor }
    private var filteredItems: [ClipboardHistoryItem] {
        service.items.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(spacing: 7) {
            controls

            if service.access != .allowed {
                accessCard
            } else if service.isEmpty {
                EmptyStateView(
                    systemImage: service.isPaused ? "pause.circle" : "doc.on.clipboard",
                    title: service.isPaused ? "Capture paused" : "Clipboard is empty",
                    subtitle: service.isPaused
                        ? "Resume when you want to capture again."
                        : "Copy text, links or images to keep them here."
                )
            } else if filteredItems.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No matches",
                    subtitle: "Try a different search."
                )
            } else {
                ScrollingStack(spacing: 5) {
                    ForEach(filteredItems) { item in row(item) }
                }
            }
        }
        .onAppear {
            service.refreshAccess()
            service.captureIfChanged()
        }
    }

    /// Why nothing is being kept, and the one thing to do about it.
    private var accessCard: some View {
        let (title, detail, action): (String, String, String) = {
            switch service.access {
            case .notYetAsked:
                return (
                    "Allow clipboard access",
                    "macOS asks before Bondex can read what you copy. Allow it once, then set it to Allow in System Settings so it stops asking.",
                    "Allow…"
                )
            case .asksEveryTime:
                return (
                    "macOS is asking every time",
                    "Set Bondex Notch to Allow under Privacy & Security › Paste from Other Apps to keep a history.",
                    "Open Settings"
                )
            case .denied, .allowed:
                return (
                    "Clipboard access is off",
                    "Allow Bondex Notch under Privacy & Security › Paste from Other Apps to keep a history.",
                    "Open Settings"
                )
            }
        }()

        return HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.attention)
                .frame(width: 28, height: 28)
                .background(Theme.attention.opacity(0.13), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: Theme.TextSize.footnote, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text(detail)
                    .font(.system(size: Theme.TextSize.caption))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Button(action) {
                if service.access == .notYetAsked {
                    service.requestAccess()
                } else {
                    service.openPrivacySettings()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(accent)
        }
        .notchRow()
    }

    private var controls: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                searchField
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(Theme.surfaceElevated, in: Capsule(style: .continuous))

            NotchButton(
                systemImage: service.isPaused ? "play.fill" : "pause.fill",
                size: 9,
                tint: service.isPaused ? accent : Theme.secondaryText
            ) {
                service.togglePaused()
            }
            .accessibilityLabel(service.isPaused ? "Resume clipboard capture" : "Pause clipboard capture")
            .help(service.isPaused ? "Resume capture" : "Pause capture")

            NotchButton(systemImage: "trash", size: 9, tint: Theme.secondaryText) {
                service.clear()
            }
            .disabled(service.isEmpty)
            .accessibilityLabel("Clear clipboard history")
            .help("Clear history")
        }
    }

    @ViewBuilder
    private var searchField: some View {
        if isRenderingOffscreen {
            // ImageRenderer cannot rasterise AppKit-backed text fields. A
            // static stand-in keeps visual regression renders meaningful.
            Text("Search clipboard")
                .font(.system(size: Theme.TextSize.footnote))
                .foregroundStyle(Theme.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField("", text: $query)
                .textFieldStyle(.plain)
                .notchPlaceholder(
                    "Search clipboard",
                    isShown: query.isEmpty,
                    font: .system(size: Theme.TextSize.footnote)
                )
                .font(.system(size: Theme.TextSize.footnote))
                .accessibilityLabel("Search clipboard history")
        }
    }

    private func row(_ item: ClipboardHistoryItem) -> some View {
        HStack(spacing: 7) {
            Button { service.copy(item) } label: {
                HStack(spacing: 8) {
                    thumbnail(item)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.system(size: Theme.TextSize.footnote, weight: .medium))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                        Text(item.detail)
                            .font(.system(size: Theme.TextSize.caption))
                            .foregroundStyle(Theme.tertiaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy \(item.title)")
            .help("Copy again")

            NotchButton(
                systemImage: item.isPinned ? "pin.fill" : "pin",
                size: 8.5,
                tint: item.isPinned ? accent : Theme.tertiaryText
            ) {
                service.togglePinned(item)
            }
            .accessibilityLabel(item.isPinned ? "Unpin \(item.title)" : "Pin \(item.title)")

            NotchButton(systemImage: "xmark", size: 8, tint: Theme.tertiaryText) {
                service.remove(item)
            }
            .accessibilityLabel("Remove \(item.title)")
        }
        .notchRow()
        .contextMenu {
            Button("Copy") { service.copy(item) }
            Button(item.isPinned ? "Unpin" : "Pin") { service.togglePinned(item) }
            Divider()
            Button("Remove") { service.remove(item) }
        }
    }

    @ViewBuilder
    private func thumbnail(_ item: ClipboardHistoryItem) -> some View {
        switch item.content {
        case .text:
            Image(systemName: item.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 25, height: 25)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.control))
        case .image:
            if let image = service.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 25, height: 25)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
            } else {
                Image(systemName: "photo")
                    .frame(width: 25, height: 25)
            }
        }
    }
}
