import Foundation

public struct PromptSnippet: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var text: String
    public var trigger: SnippetTrigger?
    public var displayOrder: Int
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        text: String,
        trigger: SnippetTrigger?,
        displayOrder: Int,
        isEnabled: Bool
    ) {
        self.id = id
        self.title = title
        self.text = text
        self.trigger = trigger
        self.displayOrder = displayOrder
        self.isEnabled = isEnabled
    }
}

public enum SnippetTrigger: Codable, Equatable, Hashable, Sendable {
    case fnKey(SnippetKey)

    public var displayLabel: String {
        switch self {
        case .fnKey(let key):
            return key.displayLabel
        }
    }
}

public struct SnippetKey: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var keyCode: Int

    public var id: Int { keyCode }

    public init(keyCode: Int) {
        self.keyCode = keyCode
    }

    public var displayLabel: String {
        if let number = Self.fnNumberByKeyCode[keyCode] {
            return "Fn + \(number)"
        }
        return "Fn + key \(keyCode)"
    }

    public static let fnNumberKeys: [SnippetKey] = [
        SnippetKey(keyCode: 18),
        SnippetKey(keyCode: 19),
        SnippetKey(keyCode: 20),
        SnippetKey(keyCode: 21),
        SnippetKey(keyCode: 23),
        SnippetKey(keyCode: 22),
        SnippetKey(keyCode: 26),
        SnippetKey(keyCode: 28),
        SnippetKey(keyCode: 25),
    ]

    public static let fnNumberTriggers: [SnippetTrigger] = fnNumberKeys.map {
        .fnKey($0)
    }

    private static let fnNumberByKeyCode: [Int: Int] = [
        18: 1,
        19: 2,
        20: 3,
        21: 4,
        23: 5,
        22: 6,
        26: 7,
        28: 8,
        25: 9,
    ]
}
