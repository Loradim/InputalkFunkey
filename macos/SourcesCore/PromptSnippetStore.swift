import Combine
import Foundation

public enum PromptSnippetStoreError: Error, Equatable {
    case validationFailed([UUID: [PromptSnippetValidationIssue]])
    case draftValidationFailed([PromptSnippetValidationIssue])
}

@MainActor
public final class PromptSnippetStore: ObservableObject {
    @Published public private(set) var snippets: [PromptSnippet]

    private let defaults: UserDefaults
    private let key: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        defaults: UserDefaults = .standard,
        key: String = Defaults.promptSnippets,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.defaults = defaults
        self.key = key
        self.encoder = encoder
        self.decoder = decoder
        self.snippets = []
        self.snippets = Self.loadSnippets(
            defaults: defaults,
            key: key,
            decoder: decoder
        )
    }

    public func reload() {
        snippets = Self.loadSnippets(defaults: defaults, key: key, decoder: decoder)
    }

    public func save(_ snippets: [PromptSnippet]) throws {
        let orderedSnippets = ordered(snippets)
        let issues = PromptSnippetValidator.validate(snippets: orderedSnippets)
        guard issues.isEmpty else {
            throw PromptSnippetStoreError.validationFailed(issues)
        }

        let data = try encoder.encode(orderedSnippets)
        defaults.set(data, forKey: key)
        self.snippets = orderedSnippets
    }

    @discardableResult
    public func save(draft: PromptSnippetDraft) throws -> PromptSnippet {
        let validation = PromptSnippetValidator.validate(draft: draft, existing: snippets)
        guard validation.isValid else {
            throw PromptSnippetStoreError.draftValidationFailed(validation.issues)
        }

        let snippet = draft.makeSnippet()
        var nextSnippets = snippets
        if let index = nextSnippets.firstIndex(where: { $0.id == snippet.id }) {
            nextSnippets[index] = snippet
        } else {
            nextSnippets.append(snippet)
        }

        try save(nextSnippets)
        return snippet
    }

    public func deleteSnippet(id: UUID) throws {
        try save(snippets.filter { $0.id != id })
    }

    public func snippet(for trigger: SnippetTrigger) -> PromptSnippet? {
        snippets.first { $0.trigger == trigger }
    }

    public func usableSnippet(for trigger: SnippetTrigger) -> PromptSnippet? {
        snippets.first {
            $0.trigger == trigger
                && $0.isEnabled
                && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public func nextDisplayOrder() -> Int {
        (snippets.map(\.displayOrder).max() ?? -1) + 1
    }

    private static func loadSnippets(
        defaults: UserDefaults,
        key: String,
        decoder: JSONDecoder
    ) -> [PromptSnippet] {
        guard let data = defaults.data(forKey: key) else {
            return []
        }

        guard let decoded = try? decoder.decode([PromptSnippet].self, from: data) else {
            return []
        }

        return sanitizeLoadedSnippets(decoded)
    }

    private static func sanitizeLoadedSnippets(_ snippets: [PromptSnippet]) -> [PromptSnippet] {
        var sanitized: [PromptSnippet] = []

        for var snippet in ordered(snippets) {
            if snippet.isEnabled {
                let result = PromptSnippetValidator.validate(
                    draft: PromptSnippetDraft(snippet: snippet),
                    existing: sanitized
                )
                if !result.isValid {
                    snippet.isEnabled = false
                }
            }
            sanitized.append(snippet)
        }

        return ordered(sanitized)
    }

    private static func ordered(_ snippets: [PromptSnippet]) -> [PromptSnippet] {
        snippets.sorted {
            if $0.displayOrder == $1.displayOrder {
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return $0.displayOrder < $1.displayOrder
        }
    }

    private func ordered(_ snippets: [PromptSnippet]) -> [PromptSnippet] {
        Self.ordered(snippets)
    }
}
