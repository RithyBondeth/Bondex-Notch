import AppKit
import SwiftUI

struct CustomShortcutsWidget: View {
    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var service: CustomActionService

    init(environment: AppEnvironment) {
        self.environment = environment
        self.settings = environment.settings
        self.service = environment.customActions
    }

    private var actions: [CustomAction] {
        Array(settings.preferences.customActions.prefix(8))
    }

    private var accent: Color { settings.effectiveAccentColor }
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 7),
        count: 4
    )

    var body: some View {
        ZStack(alignment: .bottom) {
            if actions.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "bolt.badge.plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(accent)
                    Text("No custom shortcuts yet")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add apps, Apple Shortcuts, or widget toggles in Settings.")
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .combine)
            } else {
                LazyVGrid(columns: columns, spacing: 7) {
                    ForEach(actions) { action in
                        actionButton(action)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }

            if let feedback = service.feedback {
                Label(
                    feedback.message,
                    systemImage: feedback.isError
                        ? "exclamationmark.triangle.fill"
                        : "checkmark.circle.fill"
                )
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(feedback.isError ? Color.orange : accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }
        }
        .animation(Motion.content(settings.motion), value: service.feedback)
    }

    private func actionButton(_ action: CustomAction) -> some View {
        Button {
            service.perform(action) { environment.toggleWidget($0) }
        } label: {
            HStack(spacing: 7) {
                actionIcon(action)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(action.subtitle)
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.075), lineWidth: 0.7)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
        .accessibilityHint(action.subtitle)
        .help("\(action.title) · \(action.subtitle)")
    }

    @ViewBuilder
    private func actionIcon(_ action: CustomAction) -> some View {
        if case let .application(_, path) = action.target, !path.isEmpty {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            Image(systemName: action.systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(accent.opacity(0.13), in: RoundedRectangle(
                    cornerRadius: 7, style: .continuous
                ))
        }
    }
}
