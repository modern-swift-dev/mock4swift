import Mocksmith
import Testing

@Test func callHistoryRetainsTypedArgumentsInInvocationOrder() throws {
    let member = MockMember<(key: String, value: Int), Void, Void>(name: "save")
    member.record((key: "first", value: 1))
    member.record((key: "second", value: 2))

    let history = member.callHistory { $0.value.isMultiple(of: 2) }
    #expect(history.count == 1)
    #expect(try history.onlyArgument.key == "second")
    #expect(history.arguments.map(\.value) == [2])
}

@Test func callHistoryOnlyArgumentReportsActualCount() {
    let member = MockMember<Int, Void, Void>(name: "save")
    let history = member.callHistory { _ in true }

    #expect(throws: CallHistoryError.expectedExactlyOne(member: "save", actualCount: 0)) {
        try history.onlyArgument
    }

    member.record(1)
    member.record(2)
    #expect(throws: CallHistoryError.expectedExactlyOne(member: "save", actualCount: 2)) {
        try history.onlyArgument
    }
}

@Test func callHistoryExposesOptionalPositionalArguments() {
    let member = MockMember<Int, Void, Void>(name: "save")
    let history = member.callHistory { _ in true }

    #expect(history.firstArgument == nil)
    #expect(history.lastArgument == nil)
    #expect(history.argument(at: -1) == nil)
    #expect(history.argument(at: 0) == nil)

    member.record(1)
    member.record(2)
    #expect(history.firstArgument == 1)
    #expect(history.lastArgument == 2)
    #expect(history.argument(at: 0) == 1)
    #expect(history.argument(at: 1) == 2)
    #expect(history.argument(at: 2) == nil)
}

@Test func callHistoryWaitsForRecordedCalls() async throws {
    let member = MockMember<Int, Void, Void>(name: "save")
    let history = member.callHistory { $0 > 0 }
    let waiting = Task {
        try await history.waitForCount(2, timeout: .seconds(1))
    }

    await Task.yield()
    member.record(1)
    member.record(2)
    try await waiting.value
    #expect(history.arguments == [1, 2])
}

@Test func callHistoryReturnsImmediatelyForExistingAndZeroCounts() async throws {
    let member = MockMember<Int, Void, Void>(name: "save")
    member.record(1)
    let history = member.callHistory { _ in true }

    try await history.waitForCount(1, timeout: .seconds(1))
    try await history.waitForCount(0, timeout: .seconds(1))
}

@Test func callHistoryWakesMultipleWaiters() async throws {
    let member = MockMember<Int, Void, Void>(name: "save")
    let history = member.callHistory { _ in true }
    let first = Task { try await history.waitForCount(1, timeout: .seconds(1)) }
    let second = Task { try await history.waitForCount(1, timeout: .seconds(1)) }

    await Task.yield()
    member.record(1)
    try await first.value
    try await second.value
}

@Test func callHistoryResetWakesWaitersAndResnapshots() async throws {
    let member = MockMember<Int, Void, Void>(name: "save")
    member.record(1)
    let history = member.callHistory { _ in true }
    let waiting = Task { try await history.waitForCount(2, timeout: .seconds(1)) }

    await Task.yield()
    member.reset([.invocations])
    member.record(1)
    member.record(2)
    try await waiting.value
    #expect(history.count == 2)
}

@Test func callHistoryMatcherCanReenterMember() {
    let member = MockMember<Int, Void, Void>(name: "save")
    member.record(1)
    let history = member.callHistory { value in
        member.record(value + 1)
        return value == 1
    }

    #expect(history.count == 1)
    #expect(member.invocationCount(matching: { _ in true }) == 2)
}

@Test func callHistoryHandlesCancellationBeforeWaiting() async {
    let member = MockMember<Int, Void, Void>(name: "save")
    let history = member.callHistory { _ in true }
    let waiting = Task {
        try await history.waitForCount(1, timeout: .seconds(1))
    }
    waiting.cancel()

    await #expect(throws: CancellationError.self) {
        try await waiting.value
    }
}

@Test func callHistoryDoesNotMissImmediateRecordsWhileRegistering() async throws {
    for _ in 0 ..< 100 {
        let member = MockMember<Int, Void, Void>(name: "save")
        let history = member.callHistory { _ in true }
        let waiting = Task {
            try await history.waitForCount(1, timeout: .seconds(1))
        }
        member.record(1)
        try await waiting.value
    }
}

@Test func callHistoryWaitTimeoutIncludesMatchingCount() async {
    let member = MockMember<Int, Void, Void>(name: "save")
    member.record(1)
    let history = member.callHistory { $0 > 0 }

    await #expect(throws: MockWaitError.timedOut(member: "save", expectedCount: 2, actualCount: 1)) {
        try await history.waitForCount(2, timeout: .milliseconds(10))
    }
}

@Test func callHistoryCancellationRemovesWaiter() async throws {
    let member = MockMember<Int, Void, Void>(name: "save")
    let history = member.callHistory { _ in true }
    let waiting = Task {
        try await history.waitForCount(1, timeout: .seconds(1))
    }

    await Task.yield()
    waiting.cancel()
    await #expect(throws: CancellationError.self) {
        try await waiting.value
    }

    member.record(1)
    #expect(history.count == 1)
}

@Test func callHistoryDoesNotMarkInvocationsVerified() {
    let member = MockMember<Int, Void, Void>(name: "save")
    member.record(1)

    #expect(member.callHistory(matching: { $0 == 1 }).count == 1)
    #expect(member._mocksmithUnverifiedInvocations.count == 1)
}
