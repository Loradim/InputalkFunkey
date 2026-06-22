import Foundation

public struct PromptSnippetDraft: Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var text: String
    public var trigger: SnippetTrigger?
    public var displayOrder: Int
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        title: String = "",
        text: String = "",
        trigger: SnippetTrigger? = nil,
        displayOrder: Int,
        isEnabled: Bool = false
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.trigger = trigger
        self.displayOrder = displayOrder
        self.isEnabled = isEnabled
    }

    public init(snippet: PromptSnippet) {
        self.init(
            id: snippet.id,
            title: snippet.title,
            text: snippet.text,
            trigger: snippet.trigger,
            displayOrder: snippet.displayOrder,
            isEnabled: snippet.isEnabled
        )
    }

    public func makeSnippet() -> PromptSnippet {
        PromptSnippet(
            id: id,
            title: title,
            text: text,
            trigger: trigger,
            displayOrder: displayOrder,
            isEnabled: isEnabled
        )
    }

    public func hasUnsavedChanges(comparedTo baseline: PromptSnippetDraft?) -> Bool {
        guard let baseline else { return true }
        return self != baseline
    }
}
