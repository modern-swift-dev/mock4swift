import Foundation

/// Stores mock runtime channels keyed by member and generic type specialization.
public final class GenericMockRegistry: @unchecked Sendable {
    private struct Key: Hashable {
        let key: String
        let types: [ObjectIdentifier]
    }

    private struct Entry {
        let value: Any
        let reset: ([MockScope]) -> Void
        let invocations: () -> [_Mock4SwiftInvocation]
    }

    private struct TransientEntry {
        // See StaticMockRegistry.TransientEntry for why this uses opaque ARC
        // ownership instead of `AnyObject` storage.
        let pointer: UnsafeMutableRawPointer
        let type: ObjectIdentifier
        let reset: ([MockScope]) -> Void
        let invocations: () -> [_Mock4SwiftInvocation]
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

    public func member<Arguments, Ephemeral, Output>(
        key: String,
        types: [Any.Type],
        make: () -> MockMember<Arguments, Ephemeral, Output>
    ) -> MockMember<Arguments, Ephemeral, Output> {
        member(key: key, typeIDs: types.map(ObjectIdentifier.init), make: make)
    }

    public func member<Arguments, Ephemeral, Output>(
        key: String,
        typeIDs: [ObjectIdentifier],
        make: () -> MockMember<Arguments, Ephemeral, Output>
    ) -> MockMember<Arguments, Ephemeral, Output> {
        let lookup = Key(key: key, types: typeIDs)
        precondition(lock.withLock { transientEntries[lookup] == nil }, "Generic mock member type changed for \(key)")
        if let existing = lock.withLock({ entries[lookup] }) {
            guard let member = existing.value as? MockMember<Arguments, Ephemeral, Output> else {
                preconditionFailure("Generic mock member type changed for \(key)")
            }
            return member
        }

        let candidate = make()
        return lock.withLock {
            precondition(transientEntries[lookup] == nil, "Generic mock member type changed for \(key)")
            if let existing = entries[lookup] {
                guard let member = existing.value as? MockMember<Arguments, Ephemeral, Output> else {
                    preconditionFailure("Generic mock member type changed for \(key)")
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

    public func member<Arguments: ~Copyable, Ephemeral: ~Copyable, Output: ~Copyable>(
        key: String,
        types: [Any.Type],
        make: () -> TransientMockMember<Arguments, Ephemeral, Output>
    ) -> TransientMockMember<Arguments, Ephemeral, Output> {
        member(key: key, typeIDs: types.map(ObjectIdentifier.init), make: make)
    }

    public func member<Arguments: ~Copyable, Ephemeral: ~Copyable, Output: ~Copyable>(
        key: String,
        typeIDs: [ObjectIdentifier],
        make: () -> TransientMockMember<Arguments, Ephemeral, Output>
    ) -> TransientMockMember<Arguments, Ephemeral, Output> {
        let lookup = Key(key: key, types: typeIDs)
        let type = ObjectIdentifier(TransientMockMember<Arguments, Ephemeral, Output>.self)
        precondition(lock.withLock { entries[lookup] == nil }, "Generic mock member type changed for \(key)")
        if let existing = lock.withLock({ transientEntries[lookup] }) {
            guard existing.type == type else {
                preconditionFailure("Generic mock member type changed for \(key)")
            }
            return Unmanaged<TransientMockMember<Arguments, Ephemeral, Output>>.fromOpaque(existing.pointer).takeUnretainedValue()
        }

        let candidate = make()
        return lock.withLock {
            precondition(entries[lookup] == nil, "Generic mock member type changed for \(key)")
            if let existing = transientEntries[lookup] {
                guard existing.type == type else {
                    preconditionFailure("Generic mock member type changed for \(key)")
                }
                return Unmanaged<TransientMockMember<Arguments, Ephemeral, Output>>.fromOpaque(existing.pointer).takeUnretainedValue()
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

    public func reset(_ scopes: [MockScope] = Array(MockScope.all)) {
        let resets = lock.withLock { entries.values.map(\.reset) + transientEntries.values.map(\.reset) }
        resets.forEach { $0(scopes) }
    }

    public var orderedInvocations: [_Mock4SwiftInvocation] {
        let snapshots = lock.withLock {
            entries.values.map(\.invocations) + transientEntries.values.map(\.invocations)
        }
        return snapshots.flatMap { $0() }
    }
}
