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

            if service.isEmpty {
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
        .onAppear { service.captureIfChanged() }
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
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField("Search clipboard", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
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
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.primaryText)
                            .lineLimit(1)
                        Text(item.detail)
                            .font(.system(size: 9))
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
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.surfaceElevated)
        )
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
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
        case let .image(data, _):
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 25, height: 25)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                Image(systemName: "photo")
                    .frame(width: 25, height: 25)
            }
        }
    }
}
