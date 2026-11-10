import XCTest
@testable import BondexNotch

final class CommandPaletteTests: XCTestCase {

    func testSearchRanksTitleMatchesAheadOfMetadataMatches() {
        let commands = [
            command(
                id: "metadata",
                title: "Open General settings",
                subtitle: "Clipboard preferences",
                keywords: []
            ),
            command(
                id: "title",
                title: "Clipboard history",
                subtitle: "Copy a recent item",
                keywords: []
            )
        ]

        XCTAssertEqual(
            CommandPaletteCommand.search("clipboard", in: commands).map(\.id),
            ["title", "metadata"]
        )
    }

    func testEverySearchTermMustMatchSomeCommandMetadata() {
        let commands = [
            command(
                id: "capture",
                title: "Create quick capture",
                subtitle: "Save a note",
                keywords: ["write"]
            ),
            command(
                id: "focus",
                title: "Start focus timer",
                subtitle: "Work for 25 minutes",
                keywords: ["pomodoro"]
            )
        ]

        XCTAssertEqual(
            CommandPaletteCommand.search("quick note", in: commands).map(\.id),
            ["capture"]
        )
        XCTAssertTrue(CommandPaletteCommand.search("quick timer", in: commands).isEmpty)
    }

    @MainActor
    func testSelectionWrapsAndQueryResetsIt() {
        let service = CommandPaletteService()
        service.present()

        service.moveSelection(by: -1, resultCount: 3)
        XCTAssertEqual(service.selectedIndex, 2)

        service.query = "clip"
        XCTAssertEqual(service.selectedIndex, 0)

        service.moveSelection(by: 1, resultCount: 3)
        service.moveSelection(by: 1, resultCount: 3)
        service.moveSelection(by: 1, resultCount: 3)
        XCTAssertEqual(service.selectedIndex, 0)
    }

    private func command(
        id: String,
        title: String,
        subtitle: String,
        keywords: [String]
    ) -> CommandPaletteCommand {
        CommandPaletteCommand(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImage: "command",
            category: "Test",
            keywords: keywords,
            priority: 0,
            action: .showWidget(.home)
        )
    }
}
