import AppKit
import SwiftUI

struct QuickCaptureWidget: View {
    private enum Mode { case capture, search }
    private enum Field: Hashable { case capture, search }

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var service: QuickCaptureService
    @ObservedObject private var intelligence: CaptureIntelligenceService
    @ObservedObject private var settings: SettingsStore
    @Environment(\.isRenderingOffscreen) private var isRenderingOffscreen

    @State private var mode = Mode.capture
    @State private var query = ""
    @FocusState private var focusedField: Field?

    init(environment: AppEnvironment) {
        self.environment = environment
        self.service = environment.quickCapture
        self.intelligence = environment.captureIntelligence
        self.settings = environment.settings
    }

    private var accent: Color { settings.effectiveAccentColor }
    private var filteredItems: [QuickCaptureItem] {
        service.items.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(spacing: 6) {
            inputBar

            if let enhancement = service.draftEnhancement {
                enhancementPreview(enhancement)
            } else if let error = intelligence.errorMessage,
                      settings.preferences.appleIntelligenceCaptureEnabled {
                Text(error)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Apple Intelligence: \(error)")
            }

            if service.isEmpty {
                EmptyStateView(
                    systemImage: "square.and.pencil",
                    title: "Capture something",
                    subtitle: "Type a note or paste selected text, then press Return."
                )
            } else if filteredItems.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No matches",
                    subtitle: "Try a different search."
                )
            } else {
                listHeader
                ScrollingStack(spacing: 5) {
                    ForEach(filteredItems) { item in row(item) }
                }
            }
        }
        .onAppear {
            intelligence.refreshAvailability()
            focusComposerIfRequested()
        }
        .onChange(of: service.draft) { _, _ in intelligence.clearError() }
        .onChange(of: service.focusRequest) { _, _ in focusComposerIfRequested() }
        .onChange(of: service.isEmpty) { _, isEmpty in
            if isEmpty, mode == .search { endSearch() }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: mode == .capture ? "square.and.pencil" : "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(mode == .capture ? accent : Theme.tertiaryText)

                inputField
            }
            .padding(.horizontal, 8)
            .frame(height: 26)
            .background(Theme.surfaceElevated, in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(accent.opacity(focusedField != nil ? 0.38 : 0), lineWidth: 0.8)
            )

            if mode == .capture {
                if settings.preferences.appleIntelligenceCaptureEnabled {
                    if intelligence.isEnhancing {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.68)
                            .frame(width: 24, height: 24)
                            .accessibilityLabel("Enhancing capture")
                    } else {
                        NotchButton(
                            systemImage: "sparkles",
                            size: 9,
                            tint: intelligence.availability.isAvailable
                                ? accent
                                : Theme.tertiaryText
                        ) {
                            enhanceDraft()
                        }
                        .disabled(
                            !service.canSaveDraft || !intelligence.availability.isAvailable
                        )
                        .accessibilityLabel("Enhance with Apple Intelligence")
                        .help(intelligence.availability.explanation)
                    }
                }

                NotchButton(systemImage: "doc.on.clipboard", size: 9, tint: Theme.secondaryText) {
                    _ = service.pasteFromClipboard()
                }
                .accessibilityLabel("Paste clipboard into Quick Capture")
                .help("Paste clipboard")

                NotchButton(
                    systemImage: "arrow.up",
                    size: 9,
                    tint: service.canSaveDraft ? accent : Theme.tertiaryText
                ) {
                    saveDraft()
                }
                .disabled(!service.canSaveDraft)
                .accessibilityLabel("Save Quick Capture")
                .help("Save capture")
            } else {
                NotchButton(systemImage: "xmark", size: 9, tint: Theme.secondaryText) {
                    endSearch()
                }
                .accessibilityLabel("Close capture search")
            }
        }
    }

    @ViewBuilder
    private var inputField: some View {
        if isRenderingOffscreen {
            Text(mode == .capture ? "Capture a note or link…" : "Search captures")
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if mode == .capture {
            TextField("Capture a note or link…", text: $service.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .focused($focusedField, equals: .capture)
                .onSubmit { saveDraft() }
                .accessibilityLabel("Quick Capture text")
        } else {
            TextField("Search captures", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .focused($focusedField, equals: .search)
                .accessibilityLabel("Search Quick Captures")
        }
    }

    private var listHeader: some View {
        HStack(spacing: 8) {
            Text("\(filteredItems.count) capture\(filteredItems.count == 1 ? "" : "s")")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)

            Spacer()

            if mode == .capture {
                Button("Search") { beginSearch() }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }

            Button("Clear") { service.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func enhancementPreview(_ enhancement: CaptureEnhancement) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(accent)

            Text(enhancement.title)
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)

            if !enhancement.tags.isEmpty {
                Text(enhancement.tags.map { "#" + $0 }.joined(separator: "  "))
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Theme.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: 23)
        .background(accent.opacity(0.08), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(accent.opacity(0.16), lineWidth: 0.7)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Suggested title: \(enhancement.title)")
    }

    private func row(_ item: QuickCaptureItem) -> some View {
        HStack(spacing: 7) {
            Button { service.copy(item) } label: {
                HStack(spacing: 8) {
                    Image(systemName: item.isLink ? "link" : "note.text")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 25, height: 25)
                        .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

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
            .accessibilityLabel("Copy capture: \(item.title)")
            .help("Copy capture")

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
            if item.isLink, let url = URL(string: item.text) {
                Button("Open Link") { NSWorkspace.shared.open(url) }
            }
            Button(item.isPinned ? "Unpin" : "Pin") { service.togglePinned(item) }
            Divider()
            Button("Remove") { service.remove(item) }
        }
    }

    private func beginSearch() {
        mode = .search
        DispatchQueue.main.async { focusedField = .search }
    }

    private func saveDraft() {
        if service.saveDraft() {
            environment.accessibilityAnnouncements.announce("Quick Capture saved")
        }
    }

    private func enhanceDraft() {
        Task {
            guard let enhancement = await intelligence.enhance(service.draft) else { return }
            service.applyEnhancement(enhancement)
            environment.accessibilityAnnouncements.announce("Quick Capture enhanced")
        }
    }

    private func endSearch() {
        query = ""
        mode = .capture
        DispatchQueue.main.async { focusedField = .capture }
    }

    private func focusComposerIfRequested() {
        guard service.consumeFocusRequest() else { return }
        mode = .capture
        DispatchQueue.main.async { focusedField = .capture }
    }
}
