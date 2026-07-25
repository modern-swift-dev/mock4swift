import Foundation

/// Thread-safe runtime channel that records invocations and selects matching actions and stubs.
public final class MockMember<Arguments, Ephemeral, Output>: @unchecked Sendable {
    private struct Stub {
        let id: UInt64
        let matches: (Arguments) -> Bool
        let specificity: Int
        var outcomes: [StubOutcome<Arguments, Ephemeral, Output>]
    }

    private struct Action {
        let id: UInt64
        let matches: (Arguments) -> Bool
        let specificity: Int
        let body: (Arguments, borrowing Ephemeral) -> Void
    }

    private struct ActionStub {
        let id: UInt64
        let matches: (Arguments) -> Bool
        let specificity: Int
        let outcomes: [StubOutcome<Arguments, Ephemeral, Output>]
        let body: (Arguments, borrowing Ephemeral) -> Void
        var actionEnabled = true
        var stubEnabled = true
    }

    private let lock = NSLock()
    private struct Invocation {
        let sequence: UInt64
        let arguments: Arguments
    }

    private var invocations: [Invocation] = []
    private var stubs: [Stub] = []
    private var actions: [Action] = []
    private var actionStubs: [ActionStub] = []
    private var nextOutcome: [UInt64: Int] = [:]
    private var nextID: UInt64 = 0
    private let name: String

    public init(name: String = "member") {
        self.name = name
    }

    @discardableResult
    public func addStub(
        matching: @escaping (Arguments) -> Bool,
        specificity: Int = 0,
        outcomes: [StubOutcome<Arguments, Ephemeral, Output>]
    ) -> _Mock4SwiftStubRegistration<Arguments, Ephemeral, Output> {
        precondition(!outcomes.isEmpty, "Mock stubs need at least one outcome")
        let id = lock.withLock {
            nextID += 1
            stubs.append(Stub(id: nextID, matches: matching, specificity: specificity, outcomes: outcomes))
            return nextID
        }
        return _Mock4SwiftStubRegistration { [self] outcomes in
            lock.withLock {
                guard let index = stubs.firstIndex(where: { $0.id == id }) else {
                    preconditionFailure("Mock stub registration is no longer active")
                }
                stubs[index].outcomes.append(contentsOf: outcomes)
            }
        }
    }

    public func addAction(
        matching: @escaping (Arguments) -> Bool,
        specificity: Int = 0,
        action: @escaping (Arguments, borrowing Ephemeral) -> Void
    ) {
        lock.withLock {
            nextID += 1
            actions.append(Action(id: nextID, matches: matching, specificity: specificity, body: action))
        }
    }

    public func addAction(
        matching: @escaping (Arguments) -> Bool,
        specificity: Int = 0,
        action: @escaping (Arguments) -> Void
    ) where Ephemeral == Void {
        addAction(matching: matching, specificity: specificity) { arguments, _ in
            action(arguments)
        }
    }

    public func addAction(
        matching: @escaping (Arguments) -> Bool,
        specificity: Int = 0,
        outcomes: [StubOutcome<Arguments, Ephemeral, Output>],
        action: @escaping (Arguments, borrowing Ephemeral) -> Void
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

    public func addAction(
        matching: @escaping (Arguments) -> Bool,
        specificity: Int = 0,
        outcomes: [StubOutcome<Arguments, Ephemeral, Output>],
        action: @escaping (Arguments) -> Void
    ) where Ephemeral == Void {
        addAction(matching: matching, specificity: specificity, outcomes: outcomes) { arguments, _ in
            action(arguments)
        }
    }

    public func invoke(_ arguments: Arguments, ephemeral: borrowing Ephemeral) throws -> Output {
        let sequence = nextMockInvocationSequence()
        let snapshot = lock.withLock { () -> ([Action], [Stub], [ActionStub]) in
            invocations.append(.init(sequence: sequence, arguments: arguments))
            return (actions, stubs, actionStubs)
        }

        let matchingActionStubs = snapshot.2.filter { $0.matches(arguments) }
        let action = bestAction(in: snapshot.0, arguments: arguments)
        let actionStub = bestActionStub(in: matchingActionStubs, forAction: true)
        if let actionStub, action.map({ wins(actionStub.specificity, actionStub.id, over: $0.specificity, $0.id) }) ?? true {
            actionStub.body(arguments, ephemeral)
        } else {
            action?.body(arguments, ephemeral)
        }

        let stub = bestStub(in: snapshot.1, arguments: arguments)
        let actionStubOutcome = bestActionStub(in: matchingActionStubs, forAction: false)
        let selected: (id: UInt64, outcomes: [StubOutcome<Arguments, Ephemeral, Output>])? = if let actionStubOutcome,
                                                                          stub.map({ wins(actionStubOutcome.specificity, actionStubOutcome.id, over: $0.specificity, $0.id) }) ?? true {
            (actionStubOutcome.id, actionStubOutcome.outcomes)
        } else if let stub {
            (stub.id, stub.outcomes)
        } else {
            nil
        }
        guard let selected else {
            throw MockError.unstubbed(name)
        }
        let outcome = consumeOutcome(id: selected.id, outcomes: selected.outcomes)
        switch outcome {
            case let .returnValue(value): return value
            case let .throwError(error): throw error
            case let .answer(answer): return try answer(arguments, ephemeral)
            case .asyncAnswer:
                preconditionFailure("Async mock answer requires async invocation")
        }
    }

    public func invoke(_ arguments: Arguments) throws -> Output where Ephemeral == Void {
        try invoke(arguments, ephemeral: ())
    }

    public func invokeAsync(_ arguments: Arguments, ephemeral: borrowing Ephemeral) async throws -> Output {
        let sequence = nextMockInvocationSequence()
        let snapshot = lock.withLock { () -> ([Action], [Stub], [ActionStub]) in
            invocations.append(.init(sequence: sequence, arguments: arguments))
            return (actions, stubs, actionStubs)
        }

        let matchingActionStubs = snapshot.2.filter { $0.matches(arguments) }
        let action = bestAction(in: snapshot.0, arguments: arguments)
        let actionStub = bestActionStub(in: matchingActionStubs, forAction: true)
        if let actionStub, action.map({ wins(actionStub.specificity, actionStub.id, over: $0.specificity, $0.id) }) ?? true {
            actionStub.body(arguments, ephemeral)
        } else {
            action?.body(arguments, ephemeral)
        }

        let stub = bestStub(in: snapshot.1, arguments: arguments)
        let actionStubOutcome = bestActionStub(in: matchingActionStubs, forAction: false)
        let selected: (id: UInt64, outcomes: [StubOutcome<Arguments, Ephemeral, Output>])? = if let actionStubOutcome,
                                                                                              stub.map({ wins(actionStubOutcome.specificity, actionStubOutcome.id, over: $0.specificity, $0.id) }) ?? true {
            (actionStubOutcome.id, actionStubOutcome.outcomes)
        } else if let stub {
            (stub.id, stub.outcomes)
        } else {
            nil
        }
        guard let selected else {
            throw MockError.unstubbed(name)
        }
        let outcome = consumeOutcome(id: selected.id, outcomes: selected.outcomes)
        switch outcome {
            case let .returnValue(value): return value
            case let .throwError(error): throw error
            case let .answer(answer): return try answer(arguments, ephemeral)
            case let .asyncAnswer(answer): return try await answer(arguments)
        }
    }

    public func invokeAsync(_ arguments: Arguments) async throws -> Output where Ephemeral == Void {
        try await invokeAsync(arguments, ephemeral: ())
    }

    public func record(_ arguments: Arguments) {
        let sequence = nextMockInvocationSequence()
        lock.withLock { invocations.append(.init(sequence: sequence, arguments: arguments)) }
    }

    public func invocationCount(matching: @escaping (Arguments) -> Bool) -> Int {
        let snapshot = lock.withLock { invocations }
        return snapshot.reduce(into: 0) {
            if matching($1.arguments) {
                $0 += 1
            }
        }
    }

    public var orderedInvocations: [_Mock4SwiftInvocation] {
        lock.withLock {
            invocations.map { .init(sequence: $0.sequence, member: name) }
        }
    }

    public func matchesInvocation(
        sequence: UInt64,
        matching: @escaping (Arguments) -> Bool
    ) -> Bool {
        let invocation = lock.withLock { invocations.first { $0.sequence == sequence } }
        return invocation.map { matching($0.arguments) } ?? false
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
            if scopes.contains(.invocations) {
                invocations.removeAll()
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

    private func bestAction(in candidates: [Action], arguments: Arguments) -> Action? {
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

    private func bestStub(in candidates: [Stub], arguments: Arguments) -> Stub? {
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

    private func consumeOutcome(
        id: UInt64,
        outcomes: [StubOutcome<Arguments, Ephemeral, Output>]
    ) -> StubOutcome<Arguments, Ephemeral, Output> {
        lock.withLock {
            let index = min(nextOutcome[id, default: 0], outcomes.count - 1)
            nextOutcome[id] = index + 1
            return outcomes[index]
        }
    }
}
