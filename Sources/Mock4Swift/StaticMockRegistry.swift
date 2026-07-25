import Foundation

/// Stores static mock runtime channels keyed by owner, member, and type specialization.
public final class StaticMockRegistry: @unchecked Sendable {
    private struct Key: Hashable {
        let owner: ObjectIdentifier
        let key: String
        let types: [ObjectIdentifier]
    }

    private struct Entry {
        let value: Any
        let reset: ([MockScope]) -> Void
        let invocations: () -> [_Mock4SwiftInvocation]
    }

    private struct TransientEntry {
        // `Any`/`AnyObject` erasure of a class specialized with noncopyable
        // arguments requires a newer runtime than the package's iOS 17 floor.
        let pointer: UnsafeMutableRawPointer
        let type: ObjectIdentifier
        let reset: ([MockScope]) -> Void
        let invocations: () -> [_Mock4SwiftInvocation]
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
            entries[lookup] = Entry(
                value: candidate,
                reset: candidate.reset,
                invocations: { candidate.orderedInvocations }
            )
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
                pointer: retained.toOpaque(),
                type: type,
                reset: candidate.reset,
                invocations: { candidate.orderedInvocations },
                release: retained.release
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
            entries[lookup] = Entry(
                value: candidate,
                reset: candidate.reset,
                invocations: { [] }
            )
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

    public func orderedInvocations(owner: Any.Type) -> [_Mock4SwiftInvocation] {
        let identifier = ObjectIdentifier(owner)
        let snapshots = lock.withLock {
            entries.compactMap { $0.key.owner == identifier ? $0.value.invocations : nil }
                + transientEntries.compactMap { $0.key.owner == identifier ? $0.value.invocations : nil }
        }
        return snapshots.flatMap { $0() }
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
