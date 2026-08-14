import Foundation

/// Errors thrown while waiting for recorded mock calls.
public enum MockWaitError: Error, Sendable, Equatable {
    case timedOut(member: String, expectedCount: Int, actualCount: Int)
}

/// Errors thrown while reading a call history with an invalid cardinality.
public enum CallHistoryError: Error, Sendable, Equatable {
    case expectedExactlyOne(member: String, actualCount: Int)
    case expectedAtLeastOne(member: String)
}

/// A typed, observational view of invocations recorded by one mock member.
public struct CallHistory<Arguments>: @unchecked Sendable {
    private enum WaitResult: Sendable {
        case changed
        case timedOut
    }

    private let member: String
    private let snapshot: () -> (generation: UInt64, arguments: [Arguments])
    private let waitForChange: @Sendable (UInt64) async throws -> Void

    package var _mock4SwiftMemberName: String {
        member
    }

    init(
        member: String,
        snapshot: @escaping () -> (generation: UInt64, arguments: [Arguments]),
        waitForChange: @escaping @Sendable (UInt64) async throws -> Void
    ) {
        self.member = member
        self.snapshot = snapshot
        self.waitForChange = waitForChange
    }

    /// The matching arguments in invocation order.
    public var arguments: [Arguments] {
        snapshot().arguments
    }

    /// The number of matching invocations.
    public var count: Int {
        arguments.count
    }

    /// The first matching argument, if a call was recorded.
    public var firstArgument: Arguments? {
        arguments.first
    }

    /// The last matching argument, if a call was recorded.
    public var lastArgument: Arguments? {
        arguments.last
    }

    /// The matching argument at `index`, or `nil` when the index is out of bounds.
    public func argument(at index: Int) -> Arguments? {
        let arguments = arguments
        guard arguments.indices.contains(index) else {
            return nil
        }
        return arguments[index]
    }

    /// The sole matching argument, or an error unless exactly one call was recorded.
    public var onlyArgument: Arguments {
        get throws {
            let arguments = arguments
            guard arguments.count == 1, let argument = arguments.first else {
                throw CallHistoryError.expectedExactlyOne(member: member, actualCount: arguments.count)
            }
            return argument
        }
    }

    /// Waits until at least `count` matching calls have been recorded.
    public func waitForCount(_ count: Int, timeout: Duration) async throws {
        precondition(count >= 0, "Call-history count must not be negative")
        guard count > 0 else {
            return
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            let current = snapshot()
            if current.arguments.count >= count {
                return
            }
            if clock.now >= deadline {
                throw MockWaitError.timedOut(
                    member: member,
                    expectedCount: count,
                    actualCount: current.arguments.count
                )
            }

            let result = try await waitForChange(
                after: current.generation,
                until: deadline,
                clock: clock
            )
            if result == .timedOut {
                let final = snapshot()
                if final.arguments.count >= count {
                    return
                }
                throw MockWaitError.timedOut(
                    member: member,
                    expectedCount: count,
                    actualCount: final.arguments.count
                )
            }
        }
    }

    private func waitForChange(
        after generation: UInt64,
        until deadline: ContinuousClock.Instant,
        clock: ContinuousClock
    ) async throws -> WaitResult {
        try await withThrowingTaskGroup(of: WaitResult.self) { group in
            group.addTask {
                try await waitForChange(generation)
                return .changed
            }
            group.addTask {
                try await clock.sleep(until: deadline)
                return .timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
