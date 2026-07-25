import Foundation

public struct _Mock4SwiftInvocation: Sendable, Equatable {
    public let sequence: UInt64
    public let member: String

    public init(sequence: UInt64, member: String) {
        self.sequence = sequence
        self.member = member
    }
}

private enum InvocationSequence {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var value: UInt64 = 0

    static func next() -> UInt64 {
        lock.withLock {
            precondition(value < .max, "Mock invocation sequence exhausted")
            value += 1
            return value
        }
    }
}

func nextMockInvocationSequence() -> UInt64 {
    InvocationSequence.next()
}

public final class InOrder {
    private enum SourceID: Hashable {
        case instance(ObjectIdentifier)
        case type(ObjectIdentifier)
    }

    private struct Expectation {
        let member: String
        let matches: (UInt64) -> Bool
    }

    private var sources: [SourceID: () -> [_Mock4SwiftInvocation]] = [:]
    private var expectations: [Expectation] = []

    public init() {}

    public func _append(
        source: AnyObject,
        invocations: @escaping () -> [_Mock4SwiftInvocation],
        member: String,
        matches: @escaping (UInt64) -> Bool
    ) {
        sources[.instance(ObjectIdentifier(source))] = invocations
        expectations.append(.init(member: member, matches: matches))
    }

    public func _append(
        sourceType: Any.Type,
        invocations: @escaping () -> [_Mock4SwiftInvocation],
        member: String,
        matches: @escaping (UInt64) -> Bool
    ) {
        sources[.type(ObjectIdentifier(sourceType))] = invocations
        expectations.append(.init(member: member, matches: matches))
    }

    public func verification() -> VerificationResult {
        guard let first = expectations.first else {
            return .init(success: false, message: "In-order verification needs at least one expected invocation")
        }

        let invocations = sources.values.flatMap { $0() }.sorted { $0.sequence < $1.sequence }
        guard var index = invocations.firstIndex(where: { first.matches($0.sequence) }) else {
            return .init(success: false, message: "Expected first in-order invocation \(first.member), but it was not called")
        }

        for expectation in expectations.dropFirst() {
            index += 1
            guard index < invocations.endIndex else {
                return .init(
                    success: false,
                    message: "Expected \(expectation.member) after \(invocations[index - 1].member), but no invocation followed"
                )
            }
            let actual = invocations[index]
            guard expectation.matches(actual.sequence) else {
                return .init(
                    success: false,
                    message: "Expected \(expectation.member) after \(invocations[index - 1].member), got \(actual.member)"
                )
            }
        }

        return .init(success: true, message: "Verified \(expectations.count) invocations in order")
    }
}

public protocol InOrderMock: Mock {
    associatedtype OrderExpect
    func orderExpectations(in order: InOrder) -> OrderExpect
}

public protocol InOrderStaticMock: StaticMock {
    associatedtype StaticOrderExpect
    static func orderExpectations(in order: InOrder) -> StaticOrderExpect
}

extension InOrder {
    public func expect<M: InOrderMock>(_ mock: M) -> M.OrderExpect {
        mock.orderExpectations(in: self)
    }

    public func expect<M: InOrderStaticMock>(_ type: M.Type) -> M.StaticOrderExpect {
        type.orderExpectations(in: self)
    }
}
