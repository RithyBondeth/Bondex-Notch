import SwiftUI

struct CommandPaletteView: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var palette: CommandPaletteService
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var clipboard: ClipboardHistoryService
    @ObservedObject private var captures: QuickCaptureService
    @ObservedObject private var shelf: ShelfService
    @ObservedObject private var focusTimer: FocusTimerService

    @Environment(\.isRenderingOffscreen) private var isRenderingOffscreen
    @FocusState private var searchIsFocused: Bool

    init(environment: AppEnvironment) {
        self.environment = environment
        self.palette = environment.commandPalette
        self.settings = environment.settings
        self.clipboard = environment.clipboard
        self.captures = environment.quickCapture
        self.shelf = environment.shelf
        self.focusTimer = environment.focusTimer
    }

    private var results: [CommandPaletteCommand] { environment.commandPaletteResults }
    private var accent: Color { settings.effectiveAccentColor }

    var body: some View {
        VStack(spacing: 7) {
            searchField

            if results.isEmpty {
                emptyState
            } else {
                VStack(spacing: 3) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                        CommandPaletteRow(
                            command: command,
                            isSelected: index == palette.selectedIndex,
                            accent: accent
                        ) {
                            environment.execute(command)
                        } onHover: {
                            palette.select(index, resultCount: results.count)
                        }
                    }
                }
            }

            footer
        }
        .animation(Motion.content(settings.motion), value: results.map(\.id))
        .onAppear { focusSearch() }
        .onChange(of: palette.isPresented) { _, isPresented in
            if isPresented { focusSearch() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command Palette")
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)

            if isRenderingOffscreen {
                Text("Search commands, captures, files…")
                    .font(.system(size: Theme.TextSize.title, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $palette.query)
                    .textFieldStyle(.plain)
                    .notchPlaceholder(
                        "Search commands, captures, files…",
                        isShown: palette.query.isEmpty,
                        font: .system(size: Theme.TextSize.title, weight: .medium)
                    )
                    .font(.system(size: Theme.TextSize.title, weight: .medium))
                    .focused($searchIsFocused)
                    .onSubmit { environment.executeSelectedCommand() }
                    .accessibilityLabel("Search commands, captures, files")
            }

            if !palette.query.isEmpty {
                Button {
                    palette.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            } else {
                Text(settings.preferences.commandPaletteShortcut.displayName)
                    .font(.system(size: Theme.TextSize.caption, weight: .semibold).monospaced())
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.055), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surfaceRaised.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(searchIsFocused ? 0.42 : 0.16), lineWidth: 0.8)
        )
        .shadow(color: accent.opacity(searchIsFocused ? 0.09 : 0), radius: 10)
    }

    private var emptyState: some View {
        VStack(spacing: 5) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
            Text("No matching command")
                .font(.system(size: Theme.TextSize.body, weight: .semibold))
            Text("Try an app, widget, capture, or settings page")
                .font(.system(size: Theme.TextSize.caption))
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 82)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label("Navigate", systemImage: "arrow.up.arrow.down")
            Label("Run", systemImage: "return")
            Spacer()
            Button("Close") { palette.dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.tertiaryText)
                .accessibilityHint("Returns to the current notch widget")
        }
        .font(.system(size: Theme.TextSize.caption, weight: .medium))
        .foregroundStyle(Theme.tertiaryText)
        .padding(.horizontal, 3)
    }

    private func focusSearch() {
        guard !isRenderingOffscreen else { return }
        DispatchQueue.main.async { searchIsFocused = true }
    }
}

private struct CommandPaletteRow: View {
    let command: CommandPaletteCommand
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    let onHover: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SymbolIcon(name: command.systemImage, size: 11, weight: .semibold)
                    .foregroundStyle(isSelected ? accent : Theme.secondaryText)
                    .frame(width: 26, height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? accent.opacity(0.14) : Color.white.opacity(0.045))
                    )

                VStack(alignment: .leading, spacing: 1) {
                    Text(command.title)
                        .font(.system(size: Theme.TextSize.body, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                    Text(command.subtitle)
                        .font(.system(size: Theme.TextSize.caption, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(command.category)
                    .font(.system(size: Theme.TextSize.micro, weight: .semibold))
                    .foregroundStyle(isSelected ? accent : Theme.tertiaryText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(isSelected ? 0.07 : 0.035), in: Capsule())

                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Theme.tertiaryText)
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 37)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? accent.opacity(0.2) : .clear, lineWidth: 0.7)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { onHover() }
        }
        .accessibilityLabel(command.title)
        .accessibilityValue(command.subtitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
