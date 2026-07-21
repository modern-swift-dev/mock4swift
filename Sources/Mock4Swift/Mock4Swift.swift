import Foundation

@attached(peer, names: suffixed(Mock))
public macro Mockable() = #externalMacro(module: "Mock4SwiftMacros", type: "MockableMacro")

@attached(member, names: arbitrary)
@attached(memberAttribute)
@attached(extension, conformances: Mock, StaticMock)
public macro MockableMembers() = #externalMacro(module: "Mock4SwiftMacros", type: "MockableMembersMacro")

/// Marks a requirement whose named argument or result types are noncopyable.
/// Generated mocks use a transient, count-only channel for the requirement.
@attached(peer, names: arbitrary)
public macro MockNoncopyable() = #externalMacro(module: "Mock4SwiftMacros", type: "MockNoncopyableMacro")

/// Synthesizes an inherited subscript accessor declared in a handwritten
/// `@MockableMembers` mock. Invoke it as the accessor's only expression.
@freestanding(expression)
public macro MockableAccessor<Value>() -> Value = #externalMacro(module: "Mock4SwiftMacros", type: "MockableExplicitAccessorMacro")

/// Implementation detail used by `@MockableMembers`; do not apply directly.
@attached(body)
public macro _Mock4SwiftBody(_ index: Int) = #externalMacro(module: "Mock4SwiftMacros", type: "MockableBodyMacro")

/// Implementation detail used by `@MockableMembers`; do not apply directly.
@attached(accessor)
public macro _Mock4SwiftAccessor(_ index: Int) = #externalMacro(module: "Mock4SwiftMacros", type: "MockableAccessorMacro")

public enum MockScope: Hashable, Sendable {
    case invocations
    case stubs
    case actions

    public static let all: Set<MockScope> = [.invocations, .stubs, .actions]
}

public enum MockError: Error, Equatable, Sendable {
    case unstubbed(String)
}

public struct VerificationResult: Sendable, Equatable, CustomStringConvertible {
    public let success: Bool
    public let message: String

    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }

    public var description: String { message }
}

public struct Count: Sendable, ExpressibleByIntegerLiteral, Equatable, CustomStringConvertible {
    private enum Kind: Sendable, Equatable { case exactly(Int), atLeast(Int), atMost(Int), between(Int, Int) }
    private let kind: Kind

    public init(integerLiteral value: Int) { self = .exactly(value) }
    public static var never: Count { .exactly(0) }
    public static func exactly(_ value: Int) -> Count { .init(kind: .exactly(value)) }
    public static func atLeast(_ value: Int) -> Count { .init(kind: .atLeast(value)) }
    public static func atMost(_ value: Int) -> Count { .init(kind: .atMost(value)) }
    public static func between(_ lower: Int, _ upper: Int) -> Count { .init(kind: .between(lower, upper)) }
    public static func between(_ range: ClosedRange<Int>) -> Count { .between(range.lowerBound, range.upperBound) }

    private init(kind: Kind) {
        switch kind {
        case let .exactly(value), let .atLeast(value), let .atMost(value):
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
        case let .between(lower, upper): (lower...upper).contains(value)
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

public final class ArgumentCaptor<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    public init() {}
    public var values: [Value] { lock.withLock { storage } }
    public var lastValue: Value? { lock.withLock { storage.last } }
    public func reset() { lock.withLock { storage.removeAll() } }
    fileprivate func append(_ value: Value) { lock.withLock { storage.append(value) } }
}

public struct Parameter<Value: ~Copyable> {
    private let matcher: (borrowing Value) -> Bool
    public let specificity: Int

    private init(specificity: Int, matcher: @escaping (borrowing Value) -> Bool) {
        self.specificity = specificity
        self.matcher = matcher
    }

    public static var any: Self { .init(specificity: 0) { _ in true } }
    public static func matching(_ predicate: @escaping (borrowing Value) -> Bool) -> Self {
        .init(specificity: 1, matcher: predicate)
    }
    public func matches(_ value: borrowing Value) -> Bool { matcher(value) }
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
    static func value(_ value: Value) -> Self { .value(value, by: ==) }
}

public extension Parameter where Value: AnyObject {
    static func sameInstance(_ value: Value) -> Self { .init(specificity: 1) { $0 === value } }
}

public enum StubOutcome<Output> {
    case returnValue(Output)
    case throwError(any Error)

    public static func returning(_ value: Output) -> Self { .returnValue(value) }
    public static func throwing(_ error: any Error) -> Self { .throwError(error) }
}

public protocol Mock: AnyObject {
    associatedtype Given
    associatedtype Verify
    associatedtype Perform
    func given(_ configuration: Given)
    func perform(_ configuration: Perform)
    func verification(_ configuration: Verify, count: Count) -> VerificationResult
    func resetMock(_ scopes: MockScope...)
}

public protocol StaticMock {
    associatedtype StaticGiven
    associatedtype StaticVerify
    associatedtype StaticPerform
    static func given(_ configuration: StaticGiven)
    static func perform(_ configuration: StaticPerform)
    static func verification(_ configuration: StaticVerify, count: Count) -> VerificationResult
    static func resetMock(_ scopes: MockScope...)
}

public func Given<M: Mock>(_ mock: M, _ configuration: M.Given) { mock.given(configuration) }
public func Given<M: StaticMock>(_ type: M.Type, _ configuration: M.StaticGiven) { type.given(configuration) }
public func Perform<M: Mock>(_ mock: M, _ configuration: M.Perform) { mock.perform(configuration) }
public func Perform<M: StaticMock>(_ type: M.Type, _ configuration: M.StaticPerform) { type.perform(configuration) }
public func resetMock<M: Mock>(_ mock: M, scopes: [MockScope] = Array(MockScope.all)) {
    for scope in scopes { mock.resetMock(scope) }
}
public func resetMock<M: StaticMock>(_ type: M.Type, scopes: [MockScope] = Array(MockScope.all)) {
    for scope in scopes { type.resetMock(scope) }
}

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

/// A channel for values which cannot be retained after a call, including
/// noncopyable arguments and nonescaping closures. It intentionally records
/// only a total invocation count.
public enum TransientStubOutcome<Output: ~Copyable> {
    case produce(() -> Output)
    case throwError(any Error)

    public static func producing(_ producer: @escaping () -> Output) -> Self { .produce(producer) }
    public static func throwing(_ error: any Error) -> Self { .throwError(error) }
}

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

    public init(name: String = "member") { self.name = name }

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
        let selected: (id: UInt64, outcomes: [TransientStubOutcome<Output>])?
        if let actionStubOutcome, stub.map({ wins(actionStubOutcome.specificity, actionStubOutcome.id, over: $0.specificity, $0.id) }) ?? true {
            selected = (actionStubOutcome.id, actionStubOutcome.outcomes)
        } else if let stub {
            selected = (stub.id, stub.outcomes)
        } else {
            selected = nil
        }
        guard let selected else {
            throw MockError.unstubbed(name)
        }
        switch consumeOutcome(id: selected.id, outcomes: selected.outcomes) {
        case let .produce(producer): return producer()
        case let .throwError(error): throw error
        }
    }

    public func record() { lock.withLock { count += 1 } }

    public var invocationCount: Int { lock.withLock { count } }

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
            if scopes.contains(.invocations) { count = 0 }
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

    private func bestAction(in candidates: [Action], arguments: borrowing Arguments) -> Action? {
        candidates.reduce(nil) { winner, candidate in
            guard candidate.matches(arguments) else { return winner }
            guard let winner else { return candidate }
            return wins(candidate.specificity, candidate.id, over: winner.specificity, winner.id) ? candidate : winner
        }
    }

    private func bestStub(in candidates: [Stub], arguments: borrowing Arguments) -> Stub? {
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

    private func consumeOutcome(id: UInt64, outcomes: [TransientStubOutcome<Output>]) -> TransientStubOutcome<Output> {
        lock.withLock {
            let index = min(nextOutcome[id, default: 0], outcomes.count - 1)
            nextOutcome[id] = index + 1
            return outcomes[index]
        }
    }
}

/// Synchronously forwards values such as nonescaping closures to configured
/// actions without retaining them or recording them as invocation arguments.
public final class EphemeralActionDispatcher<Arguments, Ephemeral>: @unchecked Sendable {
    private struct Action {
        let id: UInt64
        let matches: (Arguments) -> Bool
        let specificity: Int
        let body: (Arguments, borrowing Ephemeral) -> Void
    }

    private let lock = NSLock()
    private var actions: [Action] = []
    private var nextID: UInt64 = 0

    public init() {}

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

    public func dispatch(_ arguments: Arguments, ephemeral: borrowing Ephemeral) {
        let snapshot = lock.withLock { actions }
        let selected: Action? = snapshot.reduce(nil) { winner, candidate in
            guard candidate.matches(arguments) else { return winner }
            guard let winner else { return candidate }
            return candidate.specificity > winner.specificity
                || (candidate.specificity == winner.specificity && candidate.id > winner.id)
                ? candidate : winner
        }
        selected?.body(arguments, ephemeral)
    }

    public func reset(_ scopes: [MockScope] = Array(MockScope.all)) {
        guard scopes.contains(.actions) else { return }
        lock.withLock { actions.removeAll() }
    }
}

public final class StaticMockRegistry: @unchecked Sendable {
    private struct Key: Hashable {
        let owner: ObjectIdentifier
        let key: String
        let types: [ObjectIdentifier]
    }
    private struct Entry {
        let value: Any
        let reset: ([MockScope]) -> Void
    }
    private struct TransientEntry {
        // `Any`/`AnyObject` erasure of a class specialized with noncopyable
        // arguments requires a newer runtime than the package's iOS 17 floor.
        let pointer: UnsafeMutableRawPointer
        let type: ObjectIdentifier
        let reset: ([MockScope]) -> Void
        let release: () -> Void
    }

    public static let shared = StaticMockRegistry()

    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var transientEntries: [Key: TransientEntry] = [:]

    public init() {}

    deinit {
        let releases = lock.withLock { Array(transientEntries.values.map(\.release)) }
        releases.forEach { $0() }
    }

    public func member<Arguments, Output>(
        owner: Any.Type,
        key: String,
        types: [Any.Type] = [],
        make: () -> MockMember<Arguments, Output>
    ) -> MockMember<Arguments, Output> {
        member(owner: owner, key: key, typeIDs: types.map(ObjectIdentifier.init), make: make)
    }

    public func member<Arguments, Output>(
        owner: Any.Type,
        key: String,
        typeIDs: [ObjectIdentifier],
        make: () -> MockMember<Arguments, Output>
    ) -> MockMember<Arguments, Output> {
        let lookup = Key(owner: ObjectIdentifier(owner), key: key, types: typeIDs)
        precondition(lock.withLock { transientEntries[lookup] == nil }, "Static mock member type changed for \(key)")
        if let existing = lock.withLock({ entries[lookup] }) {
            guard let member = existing.value as? MockMember<Arguments, Output> else {
                preconditionFailure("Static mock member type changed for \(key)")
            }
            return member
        }

        let candidate = make()
        return lock.withLock {
            precondition(transientEntries[lookup] == nil, "Static mock member type changed for \(key)")
            if let existing = entries[lookup] {
                guard let member = existing.value as? MockMember<Arguments, Output> else {
                    preconditionFailure("Static mock member type changed for \(key)")
                }
                return member
            }
            entries[lookup] = Entry(value: candidate, reset: candidate.reset)
            return candidate
        }
    }

    public func member<Arguments: ~Copyable, Output: ~Copyable>(
        owner: Any.Type,
        key: String,
        types: [Any.Type] = [],
        make: () -> TransientMockMember<Arguments, Output>
    ) -> TransientMockMember<Arguments, Output> {
        member(owner: owner, key: key, typeIDs: types.map(ObjectIdentifier.init), make: make)
    }

    public func member<Arguments: ~Copyable, Output: ~Copyable>(
        owner: Any.Type,
        key: String,
        typeIDs: [ObjectIdentifier],
        make: () -> TransientMockMember<Arguments, Output>
    ) -> TransientMockMember<Arguments, Output> {
        let lookup = Key(owner: ObjectIdentifier(owner), key: key, types: typeIDs)
        let type = ObjectIdentifier(TransientMockMember<Arguments, Output>.self)
        precondition(lock.withLock { entries[lookup] == nil }, "Static mock member type changed for \(key)")
        if let existing = lock.withLock({ transientEntries[lookup] }) {
            guard existing.type == type else {
                preconditionFailure("Static mock member type changed for \(key)")
            }
            return Unmanaged<TransientMockMember<Arguments, Output>>.fromOpaque(existing.pointer).takeUnretainedValue()
        }

        let candidate = make()
        return lock.withLock {
            precondition(entries[lookup] == nil, "Static mock member type changed for \(key)")
            if let existing = transientEntries[lookup] {
                guard existing.type == type else {
                    preconditionFailure("Static mock member type changed for \(key)")
                }
                return Unmanaged<TransientMockMember<Arguments, Output>>.fromOpaque(existing.pointer).takeUnretainedValue()
            }
            let retained = Unmanaged.passRetained(candidate)
            transientEntries[lookup] = TransientEntry(
                pointer: retained.toOpaque(), type: type, reset: candidate.reset, release: retained.release
            )
            return candidate
        }
    }

    public func member<Arguments, Ephemeral>(
        owner: Any.Type,
        key: String,
        types: [Any.Type] = [],
        make: () -> EphemeralActionDispatcher<Arguments, Ephemeral>
    ) -> EphemeralActionDispatcher<Arguments, Ephemeral> {
        member(owner: owner, key: key, typeIDs: types.map(ObjectIdentifier.init), make: make)
    }

    public func member<Arguments, Ephemeral>(
        owner: Any.Type,
        key: String,
        typeIDs: [ObjectIdentifier],
        make: () -> EphemeralActionDispatcher<Arguments, Ephemeral>
    ) -> EphemeralActionDispatcher<Arguments, Ephemeral> {
        let lookup = Key(owner: ObjectIdentifier(owner), key: key, types: typeIDs)
        precondition(lock.withLock { transientEntries[lookup] == nil }, "Static mock member type changed for \(key)")
        if let existing = lock.withLock({ entries[lookup] }) {
            guard let dispatcher = existing.value as? EphemeralActionDispatcher<Arguments, Ephemeral> else {
                preconditionFailure("Static mock member type changed for \(key)")
            }
            return dispatcher
        }

        let candidate = make()
        return lock.withLock {
            precondition(transientEntries[lookup] == nil, "Static mock member type changed for \(key)")
            if let existing = entries[lookup] {
                guard let dispatcher = existing.value as? EphemeralActionDispatcher<Arguments, Ephemeral> else {
                    preconditionFailure("Static mock member type changed for \(key)")
                }
                return dispatcher
            }
            entries[lookup] = Entry(value: candidate, reset: candidate.reset)
            return candidate
        }
    }

    public func reset(owner: Any.Type, scopes: [MockScope] = Array(MockScope.all)) {
        let identifier = ObjectIdentifier(owner)
        let resets = lock.withLock {
            entries.compactMap { $0.key.owner == identifier ? $0.value.reset : nil }
                + transientEntries.compactMap { $0.key.owner == identifier ? $0.value.reset : nil }
        }
        resets.forEach { $0(scopes) }
    }

    public func remove(owner: Any.Type, key: String) {
        let identifier = ObjectIdentifier(owner)
        let releases = lock.withLock { () -> [() -> Void] in
            entries.keys.filter { $0.owner == identifier && $0.key == key }.forEach { entries.removeValue(forKey: $0) }
            let keys = transientEntries.keys.filter { $0.owner == identifier && $0.key == key }
            return keys.compactMap { transientEntries.removeValue(forKey: $0)?.release }
        }
        releases.forEach { $0() }
    }
}

public final class GenericMockRegistry: @unchecked Sendable {
    private struct Key: Hashable {
        let key: String
        let types: [ObjectIdentifier]
    }
    private struct Entry {
        let value: Any
        let reset: ([MockScope]) -> Void
    }
    private struct TransientEntry {
        // See StaticMockRegistry.TransientEntry for why this uses opaque ARC
        // ownership instead of `AnyObject` storage.
        let pointer: UnsafeMutableRawPointer
        let type: ObjectIdentifier
        let reset: ([MockScope]) -> Void
        let release: () -> Void
    }

    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var transientEntries: [Key: TransientEntry] = [:]

    public init() {}

    deinit {
        let releases = lock.withLock { Array(transientEntries.values.map(\.release)) }
        releases.forEach { $0() }
    }

    public func member<Arguments, Output>(
        key: String,
        types: [Any.Type],
        make: () -> MockMember<Arguments, Output>
    ) -> MockMember<Arguments, Output> {
        member(key: key, typeIDs: types.map(ObjectIdentifier.init), make: make)
    }

    public func member<Arguments, Output>(
        key: String,
        typeIDs: [ObjectIdentifier],
        make: () -> MockMember<Arguments, Output>
    ) -> MockMember<Arguments, Output> {
        let lookup = Key(key: key, types: typeIDs)
        precondition(lock.withLock { transientEntries[lookup] == nil }, "Generic mock member type changed for \(key)")
        if let existing = lock.withLock({ entries[lookup] }) {
            guard let member = existing.value as? MockMember<Arguments, Output> else {
                preconditionFailure("Generic mock member type changed for \(key)")
            }
            return member
        }

        let candidate = make()
        return lock.withLock {
            precondition(transientEntries[lookup] == nil, "Generic mock member type changed for \(key)")
            if let existing = entries[lookup] {
                guard let member = existing.value as? MockMember<Arguments, Output> else {
                    preconditionFailure("Generic mock member type changed for \(key)")
                }
                return member
            }
            entries[lookup] = Entry(value: candidate, reset: candidate.reset)
            return candidate
        }
    }

    public func member<Arguments: ~Copyable, Output: ~Copyable>(
        key: String,
        types: [Any.Type],
        make: () -> TransientMockMember<Arguments, Output>
    ) -> TransientMockMember<Arguments, Output> {
        member(key: key, typeIDs: types.map(ObjectIdentifier.init), make: make)
    }

    public func member<Arguments: ~Copyable, Output: ~Copyable>(
        key: String,
        typeIDs: [ObjectIdentifier],
        make: () -> TransientMockMember<Arguments, Output>
    ) -> TransientMockMember<Arguments, Output> {
        let lookup = Key(key: key, types: typeIDs)
        let type = ObjectIdentifier(TransientMockMember<Arguments, Output>.self)
        precondition(lock.withLock { entries[lookup] == nil }, "Generic mock member type changed for \(key)")
        if let existing = lock.withLock({ transientEntries[lookup] }) {
            guard existing.type == type else {
                preconditionFailure("Generic mock member type changed for \(key)")
            }
            return Unmanaged<TransientMockMember<Arguments, Output>>.fromOpaque(existing.pointer).takeUnretainedValue()
        }

        let candidate = make()
        return lock.withLock {
            precondition(entries[lookup] == nil, "Generic mock member type changed for \(key)")
            if let existing = transientEntries[lookup] {
                guard existing.type == type else {
                    preconditionFailure("Generic mock member type changed for \(key)")
                }
                return Unmanaged<TransientMockMember<Arguments, Output>>.fromOpaque(existing.pointer).takeUnretainedValue()
            }
            let retained = Unmanaged.passRetained(candidate)
            transientEntries[lookup] = TransientEntry(
                pointer: retained.toOpaque(), type: type, reset: candidate.reset, release: retained.release
            )
            return candidate
        }
    }

    public func member<Arguments, Ephemeral>(
        key: String,
        types: [Any.Type],
        make: () -> EphemeralActionDispatcher<Arguments, Ephemeral>
    ) -> EphemeralActionDispatcher<Arguments, Ephemeral> {
        member(key: key, typeIDs: types.map(ObjectIdentifier.init), make: make)
    }

    public func member<Arguments, Ephemeral>(
        key: String,
        typeIDs: [ObjectIdentifier],
        make: () -> EphemeralActionDispatcher<Arguments, Ephemeral>
    ) -> EphemeralActionDispatcher<Arguments, Ephemeral> {
        let lookup = Key(key: key, types: typeIDs)
        precondition(lock.withLock { transientEntries[lookup] == nil }, "Generic mock member type changed for \(key)")
        if let existing = lock.withLock({ entries[lookup] }) {
            guard let dispatcher = existing.value as? EphemeralActionDispatcher<Arguments, Ephemeral> else {
                preconditionFailure("Generic mock member type changed for \(key)")
            }
            return dispatcher
        }

        let candidate = make()
        return lock.withLock {
            precondition(transientEntries[lookup] == nil, "Generic mock member type changed for \(key)")
            if let existing = entries[lookup] {
                guard let dispatcher = existing.value as? EphemeralActionDispatcher<Arguments, Ephemeral> else {
                    preconditionFailure("Generic mock member type changed for \(key)")
                }
                return dispatcher
            }
            entries[lookup] = Entry(value: candidate, reset: candidate.reset)
            return candidate
        }
    }

    public func reset(_ scopes: [MockScope] = Array(MockScope.all)) {
        let resets = lock.withLock { entries.values.map(\.reset) + transientEntries.values.map(\.reset) }
        resets.forEach { $0(scopes) }
    }
}
