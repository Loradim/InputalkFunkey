import XCTest
@testable import InputalkFunkeyCore

final class PromptSnippetValidatorTests: XCTestCase {
    func testCodableRoundTripPreservesSnippetFields() throws {
        let snippet = PromptSnippet(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Code Review",
            text: "Review this code.",
            trigger: .fnKey(SnippetKey(keyCode: 18)),
            displayOrder: 4,
            isEnabled: true
        )

        let data = try JSONEncoder().encode(snippet)
        let decoded = try JSONDecoder().decode(PromptSnippet.self, from: data)

        XCTAssertEqual(decoded, snippet)
    }

    func testEnabledSnippetRequiresTitle() {
        let draft = PromptSnippetDraft(
            title: "   ",
            text: "Prompt",
            trigger: nil,
            displayOrder: 0,
            isEnabled: true
        )

        let result = PromptSnippetValidator.validate(draft: draft, existing: [])

        XCTAssertEqual(result.issues, [.emptyTitle])
    }

    func testEnabledSnippetRequiresPromptText() {
        let draft = PromptSnippetDraft(
            title: "Title",
            text: "\n\t ",
            trigger: nil,
            displayOrder: 0,
            isEnabled: true
        )

        let result = PromptSnippetValidator.validate(draft: draft, existing: [])

        XCTAssertEqual(result.issues, [.emptyText])
    }

    func testNoShortcutIsAllowed() {
        let draft = PromptSnippetDraft(
            title: "Title",
            text: "Prompt",
            trigger: nil,
            displayOrder: 0,
            isEnabled: true
        )

        let result = PromptSnippetValidator.validate(draft: draft, existing: [])

        XCTAssertTrue(result.isValid)
    }

    func testDuplicateEnabledTriggerReportsConflictingTitle() {
        let existing = PromptSnippet(
            title: "Code Review",
            text: "Prompt",
            trigger: .fnKey(SnippetKey(keyCode: 18)),
            displayOrder: 0,
            isEnabled: true
        )
        let draft = PromptSnippetDraft(
            title: "Refactor",
            text: "Prompt",
            trigger: .fnKey(SnippetKey(keyCode: 18)),
            displayOrder: 1,
            isEnabled: true
        )

        let result = PromptSnippetValidator.validate(draft: draft, existing: [existing])

        XCTAssertEqual(
            result.issues,
            [.duplicateEnabledTrigger(conflictingTitle: "Code Review")]
        )
    }

    func testSnippetMayKeepItsOwnTrigger() {
        let id = UUID()
        let existing = PromptSnippet(
            id: id,
            title: "Code Review",
            text: "Prompt",
            trigger: .fnKey(SnippetKey(keyCode: 18)),
            displayOrder: 0,
            isEnabled: true
        )
        let draft = PromptSnippetDraft(
            id: id,
            title: "Code Review Updated",
            text: "Prompt",
            trigger: .fnKey(SnippetKey(keyCode: 18)),
            displayOrder: 0,
            isEnabled: true
        )

        let result = PromptSnippetValidator.validate(draft: draft, existing: [existing])

        XCTAssertTrue(result.isValid)
    }

    func testDisabledSnippetsDoNotReserveShortcuts() {
        let enabled = PromptSnippet(
            title: "Code Review",
            text: "Prompt",
            trigger: .fnKey(SnippetKey(keyCode: 18)),
            displayOrder: 0,
            isEnabled: true
        )
        let disabled = PromptSnippet(
            title: "",
            text: "",
            trigger: .fnKey(SnippetKey(keyCode: 18)),
            displayOrder: 1,
            isEnabled: false
        )

        XCTAssertTrue(
            PromptSnippetValidator.validate(
                draft: PromptSnippetDraft(snippet: disabled),
                existing: [enabled]
            ).isValid
        )

        let enabledDraft = PromptSnippetDraft(
            title: "New",
            text: "Prompt",
            trigger: .fnKey(SnippetKey(keyCode: 18)),
            displayOrder: 2,
            isEnabled: true
        )

        XCTAssertEqual(
            PromptSnippetValidator.validate(draft: enabledDraft, existing: [disabled]).issues,
            []
        )
        XCTAssertEqual(
            PromptSnippetValidator.validate(draft: enabledDraft, existing: [enabled]).issues,
            [.duplicateEnabledTrigger(conflictingTitle: "Code Review")]
        )
    }
}
