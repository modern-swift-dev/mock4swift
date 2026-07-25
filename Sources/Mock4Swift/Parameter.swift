import Foundation

/// Matches a mock argument and reports matcher specificity for configuration selection.
public struct Parameter<Value: ~Copyable> {
    private let matcher: (borrowing Value) -> Bool
    public let specificity: Int

    private init(specificity: Int, matcher: @escaping (borrowing Value) -> Bool) {
        self.specificity = specificity
        self.matcher = matcher
    }

    public static var any: Self {
        .init(specificity: 0) { _ in true }
    }

    public static func matching(_ predicate: @escaping (borrowing Value) -> Bool) -> Self {
        .init(specificity: 1, matcher: predicate)
    }

    public func matches(_ value: borrowing Value) -> Bool {
        matcher(value)
    }
}

public extension Parameter where Value: Copyable {
    static func value(_ value: Value, by areEqual: @escaping (Value, Value) -> Bool) -> Self {
        .init(specificity: 1) { areEqual($0, value) }
    }

    static func capturing(_ captor: ArgumentCaptor<Value>) -> Self {
        .init(specificity: 1) { value in captor.append(value); return true }
    }
}

public extension Parameter where Value: Equatable {
    static func value(_ value: Value) -> Self {
        .value(value, by: ==)
    }
}

public extension Parameter where Value: AnyObject {
    static func sameInstance(_ value: Value) -> Self {
        .init(specificity: 1) { $0 === value }
    }
}
