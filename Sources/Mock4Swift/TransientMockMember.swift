import Foundation

/// Thread-safe, count-only runtime channel for transient arguments and results.
public final class TransientMockMember<Arguments: ~Copyable, Output: ~Copyable>: @unchecked Sendable {
    private struct Stub {
        let id: UInt64
        let matches: (borrowing Arguments) -> Bool
        let specificity: Int
        let outcomes: [TransientStubOutcome<Output>]
    }

    private struct Action {
        let id: UInt64
        let matches: (borrowing Arguments) -> Bool
        let body: (borrowing Arguments) -> Void
        let specificity: Int
    }

    private struct ActionStub {
        let id: UInt64
        let matches: (borrowing Arguments) -> Bool
        let specificity: Int
        let outcomes: [TransientStubOutcome<Output>]
        let body: (borrowing Arguments) -> Void
        var actionEnabled = true
        var stubEnabled = true
    }

    private let lock = NSLock()
    private var count = 0
    private var stubs: [Stub] = []
    private var actions: [Action] = []
    private var actionStubs: [ActionStub] = []
    private var nextOutcome: [UInt64: Int] = [:]
    private var nextID: UInt64 = 0
    private let name: String

    public init(name: String = "member") {
        self.name = name
    }

    public func addStub(
        matching: @escaping (borrowing Arguments) -> Bool,
        specificity: Int = 0,
        outcomes: [TransientStubOutcome<Output>]
    ) {
        precondition(!outcomes.isEmpty, "Mock stubs need at least one outcome")
        lock.withLock {
            nextID += 1
            stubs.append(Stub(id: nextID, matches: matching, specificity: specificity, outcomes: outcomes))
        }
    }

    public func addAction(
        matching: @escaping (borrowing Arguments) -> Bool,
        specificity: Int = 0,
        action: @escaping (borrowing Arguments) -> Void
    ) {
        lock.withLock {
            nextID += 1
            actions.append(Action(id: nextID, matches: matching, body: action, specificity: specificity))
        }
    }

    public func addAction(
        matching: @escaping (borrowing Arguments) -> Bool,
        specificity: Int = 0,
        outcomes: [TransientStubOutcome<Output>],
        action: @escaping (borrowing Arguments) -> Void
    ) {
        precondition(!outcomes.isEmpty, "Mock stubs need at least one outcome")
        lock.withLock {
            nextID += 1
            actionStubs.append(
                ActionStub(
                    id: nextID,
                    matches: matching,
                    specificity: specificity,
                    outcomes: outcomes,
                    body: action
                )
            )
        }
    }

    public func invoke(_ arguments: borrowing Arguments) throws -> Output {
        let snapshot = lock.withLock { () -> ([Action], [Stub], [ActionStub]) in
            count += 1
            return (actions, stubs, actionStubs)
        }

        let matchingActionStubs = snapshot.2.filter { $0.matches(arguments) }
        let action = bestAction(in: snapshot.0, arguments: arguments)
        let actionStub = bestActionStub(in: matchingActionStubs, forAction: true)
        if let actionStub, action.map({ wins(actionStub.specificity, actionStub.id, over: $0.specificity, $0.id) }) ?? true {
            actionStub.body(arguments)
        } else {
            action?.body(arguments)
        }

        let stub = bestStub(in: snapshot.1, arguments: arguments)
        let actionStubOutcome = bestActionStub(in: matchingActionStubs, forAction: false)
        let selected: (id: UInt64, outcomes: [TransientStubOutcome<Output>])? = if let actionStubOutcome, stub.map({ wins(
            actionStubOutcome.specificity,
            actionStubOutcome.id,
            over: $0.specificity,
            $0.id
        ) }) ?? true {
            (actionStubOutcome.id, actionStubOutcome.outcomes)
        } else if let stub {
            (stub.id, stub.outcomes)
        } else {
            nil
        }
        guard let selected else {
            throw MockError.unstubbed(name)
        }
        switch consumeOutcome(id: selected.id, outcomes: selected.outcomes) {
            case let .produce(producer): return producer()
            case let .throwError(error): throw error
        }
    }

    public func record() {
        lock.withLock { count += 1 }
    }

    public var invocationCount: Int {
        lock.withLock { count }
    }

    public func verification(count: Count) -> VerificationResult {
        let actual = invocationCount
        let success = count.matches(actual)
        return .init(
            success: success,
            message: success ? "Verified \(count) for \(name)" : "Expected \(count) for \(name), got \(actual)"
        )
    }

    public func reset(_ scopes: [MockScope] = Array(MockScope.all)) {
        let scopes = Set(scopes)
        lock.withLock {
            if scopes.contains(.invocations) {
                count = 0
            }
            if scopes.contains(.stubs) {
                stubs.removeAll()
                nextOutcome.removeAll()
                for index in actionStubs.indices {
                    actionStubs[index].stubEnabled = false
                }
            }
            if scopes.contains(.actions) {
                actions.removeAll()
                for index in actionStubs.indices {
                    actionStubs[index].actionEnabled = false
                }
            }
            actionStubs.removeAll { !$0.actionEnabled && !$0.stubEnabled }
        }
    }

    private func bestAction(in candidates: [Action], arguments: borrowing Arguments) -> Action? {
        candidates.reduce(nil) { winner, candidate in
            guard candidate.matches(arguments) else {
                return winner
            }
            guard let winner else {
                return candidate
            }
            return wins(candidate.specificity, candidate.id, over: winner.specificity, winner.id) ? candidate : winner
        }
    }

    private func bestStub(in candidates: [Stub], arguments: borrowing Arguments) -> Stub? {
        candidates.reduce(nil) { winner, candidate in
            guard candidate.matches(arguments) else {
                return winner
            }
            guard let winner else {
                return candidate
            }
            return wins(candidate.specificity, candidate.id, over: winner.specificity, winner.id) ? candidate : winner
        }
    }

    private func bestActionStub(in candidates: [ActionStub], forAction: Bool) -> ActionStub? {
        candidates.reduce(nil) { winner, candidate in
            guard forAction ? candidate.actionEnabled : candidate.stubEnabled else {
                return winner
            }
            guard let winner else {
                return candidate
            }
            return wins(candidate.specificity, candidate.id, over: winner.specificity, winner.id) ? candidate : winner
        }
    }

    private func wins(_ specificity: Int, _ id: UInt64, over otherSpecificity: Int, _ otherID: UInt64) -> Bool {
        specificity > otherSpecificity || (specificity == otherSpecificity && id > otherID)
    }

    private func consumeOutcome(id: UInt64, outcomes: [TransientStubOutcome<Output>]) -> TransientStubOutcome<Output> {
        lock.withLock {
            let index = min(nextOutcome[id, default: 0], outcomes.count - 1)
            nextOutcome[id] = index + 1
            return outcomes[index]
        }
    }
}
