import SwiftUI

/// Drag files in, drag them back out somewhere else.
struct ShelfWidget: View {

    @ObservedObject var environment: AppEnvironment
    @ObservedObject private var service: ShelfService
    @ObservedObject private var notch: NotchViewModel

    init(environment: AppEnvironment) {
        self.environment = environment
        self.service = environment.shelf
        self.notch = environment.notch
    }

    @Environment(\.notchTint) private var accent

    var body: some View {
        VStack(spacing: 8) {
            if service.isEmpty {
                EmptyStateView(
                    systemImage: "tray",
                    title: notch.isDropTargeted ? "Release to add" : "Shelf is empty",
                    subtitle: "Drag files onto the notch to park them here."
                )
            } else {
                header
                grid
            }
        }
    }

    private var header: some View {
        HStack {
            Text("\(service.items.count) item\(service.items.count == 1 ? "" : "s")")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
            Spacer()
            Button("Clear") { service.clear() }
                .buttonStyle(.plain)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private var grid: some View {
        ScrollingStack(axis: .horizontal, spacing: 8) {
            ForEach(service.items) { item in
                tile(item)
            }
        }
    }

    private func tile(_ item: ShelfItem) -> some View {
        VStack(spacing: 5) {
            Image(nsImage: item.icon)
                .resizable()
                .frame(width: 34, height: 34)

            Text(item.name)
                .font(.system(size: 9))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 62)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surfaceElevated)
        )
        .overlay(alignment: .topTrailing) {
            NotchButton(systemImage: "xmark.circle.fill", size: 9, tint: Theme.tertiaryText) {
                service.remove(item)
            }
            .offset(x: 4, y: -4)
        }
        // Dragging out hands the receiver the original file URL — nothing is
        // copied into the shelf, so this is always the real file.
        .onDrag {
            NSItemProvider(contentsOf: item.url) ?? NSItemProvider()
        }
        .contextMenu {
            Button("Reveal in Finder") { service.reveal(item) }
            Button("Remove") { service.remove(item) }
        }
    }
}
