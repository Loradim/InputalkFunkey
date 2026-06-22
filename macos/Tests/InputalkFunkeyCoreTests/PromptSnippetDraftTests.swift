import XCTest
@testable import InputalkFunkeyCore

final class PromptSnippetDraftTests: XCTestCase {
    func testDraftWithSameBaselineIsNotDirty() {
        let draft = PromptSnippetDraft(
            title: "Code Review",
            text: "Review this.",
            trigger: .fnKey(SnippetKey(keyCode: 18)),
            displayOrder: 0,
            isEnabled: true
        )

        XCTAssertFalse(draft.hasUnsavedChanges(comparedTo: draft))
    }

    func testDraftWithChangedTitleIsDirty() {
        let baseline = PromptSnippetDraft(
            title: "Code Review",
            text: "Review this.",
            trigger: .fnKey(SnippetKey(keyCode: 18)),
            displayOrder: 0,
            isEnabled: true
        )
        var draft = baseline
        draft.title = "Refactor"

        XCTAssertTrue(draft.hasUnsavedChanges(comparedTo: baseline))
    }

    func testDraftWithoutBaselineIsDirty() {
        let draft = PromptSnippetDraft(displayOrder: 0)

        XCTAssertTrue(draft.hasUnsavedChanges(comparedTo: nil))
    }
}
