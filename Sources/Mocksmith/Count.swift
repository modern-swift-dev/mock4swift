import Foundation

/// Describes the number of matching invocations required for verification.
public struct Count: Sendable, ExpressibleByIntegerLiteral, Equatable, CustomStringConvertible {
    private enum Kind: Sendable, Equatable { case exactly(Int), atLeast(Int), atMost(Int), between(Int, Int) }
    private let kind: Kind

    public init(integerLiteral value: Int) {
        self = .exactly(value)
    }

    public static var never: Count {
        .exactly(0)
    }

    public static func exactly(_ value: Int) -> Count {
        .init(kind: .exactly(value))
    }

    public static func atLeast(_ value: Int) -> Count {
        .init(kind: .atLeast(value))
    }

    public static func atMost(_ value: Int) -> Count {
        .init(kind: .atMost(value))
    }

    public static func between(_ lower: Int, _ upper: Int) -> Count {
        .init(kind: .between(lower, upper))
    }

    public static func between(_ range: ClosedRange<Int>) -> Count {
        .between(range.lowerBound, range.upperBound)
    }

    private init(kind: Kind) {
        switch kind {
            case let .exactly(value),
                 let .atLeast(value),
                 let .atMost(value):
                precondition(value >= 0, "Mock counts cannot be negative")
            case let .between(lower, upper):
                precondition(lower >= 0 && upper >= lower, "Mock count range is invalid")
        }
        self.kind = kind
    }

    public func matches(_ value: Int) -> Bool {
        switch kind {
            case let .exactly(expected): value == expected
            case let .atLeast(minimum): value >= minimum
            case let .atMost(maximum): value <= maximum
            case let .between(lower, upper): (lower ... upper).contains(value)
        }
    }

    public var description: String {
        switch kind {
            case let .exactly(value): "exactly \(value) times"
            case let .atLeast(value): "at least \(value) times"
            case let .atMost(value): "at most \(value) times"
            case let .between(lower, upper): "between \(lower) and \(upper) times"
        }
    }
}
