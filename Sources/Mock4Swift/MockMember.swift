import Foundation

/// Thread-safe runtime channel that records invocations and selects matching actions and stubs.
public final class MockMember<Arguments, Output>: @unchecked Sendable {
    private struct Stub {
        let id: UInt64
        let matches: (Arguments) -> Bool
        let specificity: Int
        let outcomes: [StubOutcome<Output>]
    }
    private struct Action {
        let id: UInt64
        let matches: (Arguments) -> Bool
        let specificity: Int
        let body: (Arguments) -> Void
    }
    private struct ActionStub {
        let id: UInt64
        let matches: (Arguments) -> Bool
        let specificity: Int
        let outcomes: [StubOutcome<Output>]
        let body: (Arguments) -> Void
        var actionEnabled = true
        var stubEnabled = true
    }

    private let lock = NSLock()
    private var invocations: [Arguments] = []
    private var stubs: [Stub] = []
    private var actions: [Action] = []
    private var actionStubs: [ActionStub] = []
    private var nextOutcome: [UInt64: Int] = [:]
    private var nextID: UInt64 = 0
    private let name: String

    public init(name: String = "member") { self.name = name }

    public func addStub(
        matching: @escaping (Arguments) -> Bool,
        specificity: Int = 0,
        outcomes: [StubOutcome<Output>]
    ) {
        precondition(!outcomes.isEmpty, "Mock stubs need at least one outcome")
        lock.withLock {
            nextID += 1
            stubs.append(Stub(id: nextID, matches: matching, specificity: specificity, outcomes: outcomes))
        }
    }

    public func addAction(
        matching: @escaping (Arguments) -> Bool,
        specificity: Int = 0,
        action: @escaping (Arguments) -> Void
    ) {
        lock.withLock {
            nextID += 1
            actions.append(Action(id: nextID, matches: matching, specificity: specificity, body: action))
        }
    }

    public func addAction(
        matching: @escaping (Arguments) -> Bool,
        specificity: Int = 0,
        outcomes: [StubOutcome<Output>],
        action: @escaping (Arguments) -> Void
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

    public func invoke(_ arguments: Arguments) throws -> Output {
        let snapshot = lock.withLock { () -> ([Action], [Stub], [ActionStub]) in
            invocations.append(arguments)
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
        let selected: (id: UInt64, outcomes: [StubOutcome<Output>])?
        if let actionStubOutcome, stub.map({ wins(actionStubOutcome.specificity, actionStubOutcome.id, over: $0.specificity, $0.id) }) ?? true {
            selected = (actionStubOutcome.id, actionStubOutcome.outcomes)
        } else if let stub {
            selected = (stub.id, stub.outcomes)
        } else {
            selected = nil
        }
        guard let selected else { throw MockError.unstubbed(name) }
        let outcome = consumeOutcome(id: selected.id, outcomes: selected.outcomes)
        switch outcome {
        case let .returnValue(value): return value
        case let .throwError(error): throw error
        }
    }

    public func record(_ arguments: Arguments) {
        lock.withLock { invocations.append(arguments) }
    }

    public func invocationCount(matching: @escaping (Arguments) -> Bool) -> Int {
        let snapshot = lock.withLock { invocations }
        return snapshot.reduce(into: 0) { if matching($1) { $0 += 1 } }
    }

    public func verification(matching: @escaping (Arguments) -> Bool, count: Count) -> VerificationResult {
        let actual = invocationCount(matching: matching)
        let success = count.matches(actual)
        return .init(
            success: success,
            message: success ? "Verified \(count) for \(name)" : "Expected \(count) for \(name), got \(actual)"
        )
    }

    public func reset(_ scopes: [MockScope] = Array(MockScope.all)) {
        let scopes = Set(scopes)
        lock.withLock {
            if scopes.contains(.invocations) { invocations.removeAll() }
            if scopes.contains(.stubs) {
                stubs.removeAll()
                nextOutcome.removeAll()
                for index in actionStubs.indices { actionStubs[index].stubEnabled = false }
            }
            if scopes.contains(.actions) {
                actions.removeAll()
                for index in actionStubs.indices { actionStubs[index].actionEnabled = false }
            }
            actionStubs.removeAll { !$0.actionEnabled && !$0.stubEnabled }
        }
    }

    private func bestAction(in candidates: [Action], arguments: Arguments) -> Action? {
        candidates.reduce(nil) { winner, candidate in
            guard candidate.matches(arguments) else { return winner }
            guard let winner else { return candidate }
            return wins(candidate.specificity, candidate.id, over: winner.specificity, winner.id) ? candidate : winner
        }
    }

    private func bestStub(in candidates: [Stub], arguments: Arguments) -> Stub? {
        candidates.reduce(nil) { winner, candidate in
            guard candidate.matches(arguments) else { return winner }
            guard let winner else { return candidate }
            return wins(candidate.specificity, candidate.id, over: winner.specificity, winner.id) ? candidate : winner
        }
    }

    private func bestActionStub(in candidates: [ActionStub], forAction: Bool) -> ActionStub? {
        candidates.reduce(nil) { winner, candidate in
            guard forAction ? candidate.actionEnabled : candidate.stubEnabled else { return winner }
            guard let winner else { return candidate }
            return wins(candidate.specificity, candidate.id, over: winner.specificity, winner.id) ? candidate : winner
        }
    }

    private func wins(_ specificity: Int, _ id: UInt64, over otherSpecificity: Int, _ otherID: UInt64) -> Bool {
        specificity > otherSpecificity || (specificity == otherSpecificity && id > otherID)
    }

    private func consumeOutcome(id: UInt64, outcomes: [StubOutcome<Output>]) -> StubOutcome<Output> {
        lock.withLock {
            let index = min(nextOutcome[id, default: 0], outcomes.count - 1)
            nextOutcome[id] = index + 1
            return outcomes[index]
        }
    }
}
