import Foundation

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
            guard candidate.matches(arguments) else {
                return winner
            }
            guard let winner else {
                return candidate
            }
            return candidate.specificity > winner.specificity
                || (candidate.specificity == winner.specificity && candidate.id > winner.id)
                ? candidate : winner
        }
        selected?.body(arguments, ephemeral)
    }

    public func reset(_ scopes: [MockScope] = Array(MockScope.all)) {
        guard scopes.contains(.actions) else {
            return
        }
        lock.withLock { actions.removeAll() }
    }
}
