import Foundation

/// Selects mock state categories cleared by reset operations.
public enum MockScope: Hashable, Sendable {
    case invocations
    case stubs
    case actions

    public static let all: Set<MockScope> = [.invocations, .stubs, .actions]
}
