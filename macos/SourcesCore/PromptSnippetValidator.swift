import Foundation

public enum PromptSnippetValidationIssue: Equatable, Sendable {
    case emptyTitle
    case emptyText
    case duplicateEnabledTrigger(conflictingTitle: String)

    public func message(trigger: SnippetTrigger?) -> String {
        switch self {
        case .emptyTitle:
            return "Title is required before this snippet can be enabled."
        case .emptyText:
            return "Prompt text is required before this snippet can be enabled."
        case .duplicateEnabledTrigger(let conflictingTitle):
            let label = trigger?.displayLabel ?? "This shortcut"
            return "\(label) is already used by enabled snippet \"\(conflictingTitle)\"."
        }
    }

    public func saveUnavailableExplanation(trigger: SnippetTrigger?) -> String {
        switch self {
        case .emptyTitle:
            return "the title is empty"
        case .emptyText:
            return "the prompt text is empty"
        case .duplicateEnabledTrigger(let conflictingTitle):
            let label = trigger?.displayLabel ?? "this shortcut"
            return "\(label) is already used by \"\(conflictingTitle)\""
        }
    }
}

public struct PromptSnippetValidationResult: Equatable, Sendable {
    public var issues: [PromptSnippetValidationIssue]

    public var isValid: Bool {
        issues.isEmpty
    }

    public init(issues: [PromptSnippetValidationIssue]) {
        self.issues = issues
    }
}

public enum PromptSnippetValidator {
    public static func validate(
        draft: PromptSnippetDraft,
        existing snippets: [PromptSnippet]
    ) -> PromptSnippetValidationResult {
        guard draft.isEnabled else {
            return PromptSnippetValidationResult(issues: [])
        }

        var issues: [PromptSnippetValidationIssue] = []

        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.emptyTitle)
        }

        if draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(.emptyText)
        }

        if let trigger = draft.trigger,
            let conflict = snippets.first(where: {
                $0.id != draft.id && $0.isEnabled && $0.trigger == trigger
            })
        {
            issues.append(.duplicateEnabledTrigger(conflictingTitle: conflict.title))
        }

        return PromptSnippetValidationResult(issues: issues)
    }

    public static func validate(snippets: [PromptSnippet]) -> [UUID: [PromptSnippetValidationIssue]] {
        var issuesByID: [UUID: [PromptSnippetValidationIssue]] = [:]

        for snippet in snippets {
            let result = validate(
                draft: PromptSnippetDraft(snippet: snippet),
                existing: snippets
            )
            if !result.issues.isEmpty {
                issuesByID[snippet.id] = result.issues
            }
        }

        return issuesByID
    }
}
