import XCTest
@testable import InputalkFunkeyCore

final class PromptSnippetStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "InputalkFunkeyCoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testPromptSnippetsDefaultKeyIsExact() {
        XCTAssertEqual(Defaults.promptSnippets, "promptSnippets")
    }

    @MainActor
    func testStoreStartsEmptyWhenKeyIsMissing() {
        let store = PromptSnippetStore(defaults: defaults)

        XCTAssertEqual(store.snippets, [])
    }

    @MainActor
    func testStoreReturnsEmptyWhenStoredValueCannotDecode() {
        defaults.set("not json data", forKey: Defaults.promptSnippets)

        let store = PromptSnippetStore(defaults: defaults)

        XCTAssertEqual(store.snippets, [])
    }

    @MainActor
    func testStoreSavesAndReloadsRoundTripInDisplayOrder() throws {
        let fn2 = SnippetTrigger.fnKey(SnippetKey(keyCode: 19))
        let first = PromptSnippet(
            title: "Second",
            text: "Prompt 2",
            trigger: fn2,
            displayOrder: 20,
            isEnabled: true
        )
        let second = PromptSnippet(
            title: "First",
            text: "Prompt 1",
            trigger: .fnKey(SnippetKey(keyCode: 18)),
            displayOrder: 10,
            isEnabled: true
        )

        let store = PromptSnippetStore(defaults: defaults)
        try store.save([first, second])

        let reloaded = PromptSnippetStore(defaults: defaults)

        XCTAssertEqual(reloaded.snippets.map(\.title), ["First", "Second"])
        XCTAssertEqual(reloaded.usableSnippet(for: fn2)?.title, "Second")
    }

    @MainActor
    func testStoreLoadsInvalidEnabledSnippetsButDisablesThem() throws {
        let invalid = PromptSnippet(
            title: "No Text",
            text: "",
            trigger: .fnKey(SnippetKey(keyCode: 18)),
            displayOrder: 0,
            isEnabled: true
        )
        let data = try JSONEncoder().encode([invalid])
        defaults.set(data, forKey: Defaults.promptSnippets)

        let store = PromptSnippetStore(defaults: defaults)

        XCTAssertEqual(store.snippets.count, 1)
        XCTAssertEqual(store.snippets[0].title, "No Text")
        XCTAssertFalse(store.snippets[0].isEnabled)
        XCTAssertNil(store.usableSnippet(for: .fnKey(SnippetKey(keyCode: 18))))
    }

    @MainActor
    func testStoreDisablesLaterDuplicateEnabledTriggerOnLoad() throws {
        let trigger = SnippetTrigger.fnKey(SnippetKey(keyCode: 18))
        let first = PromptSnippet(
            title: "First",
            text: "Prompt 1",
            trigger: trigger,
            displayOrder: 0,
            isEnabled: true
        )
        let duplicate = PromptSnippet(
            title: "Duplicate",
            text: "Prompt 2",
            trigger: trigger,
            displayOrder: 1,
            isEnabled: true
        )
        let data = try JSONEncoder().encode([first, duplicate])
        defaults.set(data, forKey: Defaults.promptSnippets)

        let store = PromptSnippetStore(defaults: defaults)

        XCTAssertTrue(store.snippets[0].isEnabled)
        XCTAssertFalse(store.snippets[1].isEnabled)
        XCTAssertEqual(store.usableSnippet(for: trigger)?.title, "First")
    }

    @MainActor
    func testStoreRejectsInvalidEnabledSnippetBeforeSaving() {
        let store = PromptSnippetStore(defaults: defaults)
        let invalid = PromptSnippet(
            title: "",
            text: "Prompt",
            trigger: nil,
            displayOrder: 0,
            isEnabled: true
        )

        XCTAssertThrowsError(try store.save([invalid])) { error in
            guard case PromptSnippetStoreError.validationFailed(let issues) = error else {
                return XCTFail("Expected validation error, got \(error)")
            }
            XCTAssertEqual(Array(issues.values).flatMap { $0 }, [.emptyTitle])
        }
    }
}
