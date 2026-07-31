import SwiftUI

struct FileActivityWidget: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var service: FileActivityService

    init(environment: AppEnvironment) {
        self.environment = environment
        self.service = environment.files
    }

    @Environment(\.notchTint) private var accent

    var body: some View {
        if service.accessDenied {
            EmptyStateView(
                systemImage: "folder.badge.questionmark",
                title: "Downloads folder not readable",
                subtitle: "Grant access in System Settings ›\nPrivacy & Security › Files and Folders."
            )
        } else if service.activities.isEmpty {
            EmptyStateView(
                systemImage: "arrow.down.circle",
                title: "No recent transfers",
                subtitle: "Downloads appear here as they arrive."
            )
        } else {
            list
        }
    }

    private var list: some View {
        ScrollingStack(spacing: 6) {
            ForEach(service.activities) { activity in
                row(activity)
            }
        }
    }

    private func row(_ activity: FileActivity) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: activity.icon)
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(activity.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if activity.isComplete {
                    Text(activity.byteCount.formattedBytes)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.tertiaryText)
                } else {
                    // No public API reports a download's expected total size,
                    // so progress is shown as bytes received plus live rate
                    // rather than a percentage that would have to be invented.
                    HStack(spacing: 5) {
                        Text(activity.byteCount.formattedBytes)
                        if activity.bytesPerSecond > 1024 {
                            Text("· \(Int64(activity.bytesPerSecond).formattedBytes)/s")
                        }
                    }
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                }
            }

            Spacer(minLength: 4)

            if activity.isComplete {
                NotchButton(systemImage: "magnifyingglass", size: 10, tint: Theme.secondaryText) {
                    service.reveal(activity)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(accent)
            }
        }
        .notchCard()
    }
}
