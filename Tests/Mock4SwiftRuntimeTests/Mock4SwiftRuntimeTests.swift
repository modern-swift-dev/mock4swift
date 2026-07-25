import Mock4Swift
import Testing

@Test func memberUsesSpecificNewestStubAndRepeatsLastOutcome() throws {
    let member = MockMember<String, Void, Int>()
    member.addStub(matching: { _ in true }, outcomes: [.returning(1)])
    member.addStub(matching: { $0 == "x" }, specificity: 1, outcomes: [.returning(2), .returning(3)])
    member.addStub(matching: { $0 == "x" }, specificity: 1, outcomes: [.returning(4)])
    #expect(try member.invoke("x") == 4)
    #expect(try member.invoke("other") == 1)
}

@Test func moreSpecificStubBeatsNewerRegistration() throws {
    let member = MockMember<String, Void, Int>()
    member.addStub(matching: { $0 == "x" }, specificity: 1, outcomes: [.returning(1)])
    member.addStub(matching: { _ in true }, outcomes: [.returning(2)])
    #expect(try member.invoke("x") == 1)
}

@Test func mixedOutcomesConsumeInOrderAndRepeatLast() throws {
    enum Failure: Error { case expected }
    let member = MockMember<Void, Void, Int>()
    member.addStub(
        matching: { _ in true },
        outcomes: [.returning(1), .throwing(Failure.expected), .returning(3)]
    )
    #expect(try member.invoke(()) == 1)
    #expect(throws: Failure.expected) { try member.invoke(()) }
    #expect(try member.invoke(()) == 3)
    #expect(try member.invoke(()) == 3)
}

@Test func appendableStubRegistrationBuildsMixedOutcomeSequence() throws {
    enum Failure: Error { case expected }
    let member = MockMember<Void, Void, Int>(name: "value")
    let registration = member.addStub(matching: { _ in true }, outcomes: [.returning(1)])
    registration.append([.throwing(Failure.expected), .returning(3)])

    #expect(try member.invoke(()) == 1)
    #expect(throws: Failure.expected) { try member.invoke(()) }
    #expect(try member.invoke(()) == 3)
    #expect(try member.invoke(()) == 3)
}

@Test func answersUseArgumentsAndMixWithFixedOutcomes() throws {
    enum Failure: Error { case expected }
    let member = MockMember<Int, Void, Int>()
    member.addStub(
        matching: { _ in true },
        outcomes: [
            .answering { arguments, _ in arguments * 2 },
            .returning(10),
            .throwing(Failure.expected),
            .answering { arguments, _ in arguments + 1 }
        ]
    )

    #expect(try member.invoke(2) == 4)
    #expect(try member.invoke(3) == 10)
    #expect(throws: Failure.expected) { try member.invoke(4) }
    #expect(try member.invoke(5) == 6)
    #expect(try member.invoke(6) == 7)
}

@Test func asyncAnswersSuspendOutsideMemberLock() async throws {
    let member = MockMember<Int, Void, Int>()
    member.addStub(
        matching: { _ in true },
        outcomes: [.answering { arguments async in
            #expect(member.invocationCount(matching: { _ in true }) == 1)
            await Task.yield()
            return arguments * 2
        }]
    )

    #expect(try await member.invokeAsync(4) == 8)
}

@Test func asyncInvocationRunsEphemeralActionBeforeAnswer() async throws {
    let member = MockMember<Int, Int, Int>()
    var actionValue = 0
    member.addAction(matching: { _ in true }) { arguments, ephemeral in
        actionValue = arguments + ephemeral
    }
    member.addStub(
        matching: { _ in true },
        outcomes: [.answering { arguments async in
            #expect(actionValue == 7)
            await Task.yield()
            return arguments * 2
        }]
    )

    #expect(try await member.invokeAsync(4, ephemeral: 3) == 8)
}

@Test func answerBuildersAppendMixedSequence() throws {
    enum Failure: Error { case expected }
    typealias Answer = (Int) throws -> Int
    let member = MockMember<Int, Void, Int>()
    let builder = _Mock4SwiftThrowingReturnStub<Int, Void, Int, Failure, Answer>(
        apply: { member.addStub(matching: { _ in true }, outcomes: $0) },
        answer: { answer in .answering { arguments, _ in try answer(arguments) } }
    )
    builder.willAnswer { arguments in arguments }
        .thenReturn(2)
        .thenThrow(.expected)
        .thenAnswer { arguments in arguments * 2 }

    #expect(try member.invoke(1) == 1)
    #expect(try member.invoke(1) == 2)
    #expect(throws: Failure.expected) { try member.invoke(1) }
    #expect(try member.invoke(3) == 6)
}

@Test func inOrderUsesStrictAdjacencyAcrossSources() throws {
    let first = MockMember<Int, Void, Void>(name: "first")
    let second = MockMember<Int, Void, Void>(name: "second")
    first.addStub(matching: { _ in true }, outcomes: [.returning(())])
    second.addStub(matching: { _ in true }, outcomes: [.returning(())])

    try first.invoke(1)
    try second.invoke(2)
    try first.invoke(3)

    let success = InOrder()
    success._append(
        source: first,
        invocations: { first.orderedInvocations },
        member: "first",
        matches: { first.matchesInvocation(sequence: $0, matching: { $0 == 1 }) }
    )
    success._append(
        source: second,
        invocations: { second.orderedInvocations },
        member: "second",
        matches: { second.matchesInvocation(sequence: $0, matching: { $0 == 2 }) }
    )
    success._append(
        source: first,
        invocations: { first.orderedInvocations },
        member: "first",
        matches: { first.matchesInvocation(sequence: $0, matching: { $0 == 3 }) }
    )
    #expect(success.verification().success)

    let failure = InOrder()
    failure._append(
        source: first,
        invocations: { first.orderedInvocations },
        member: "first",
        matches: { first.matchesInvocation(sequence: $0, matching: { $0 == 1 }) }
    )
    failure._append(
        source: first,
        invocations: { first.orderedInvocations },
        member: "first",
        matches: { first.matchesInvocation(sequence: $0, matching: { $0 == 3 }) }
    )
    failure._append(
        source: second,
        invocations: { second.orderedInvocations },
        member: "second",
        matches: { second.matchesInvocation(sequence: $0, matching: { $0 == 2 }) }
    )
    let result = failure.verification()
    #expect(!result.success)
    #expect(result.message.contains("got second"))
}

@Test func actionAndCaptorWorkWithoutLeakingResetState() throws {
    let member = MockMember<Int, Void, Int>()
    let captor = ArgumentCaptor<Int>()
    let parameter = Parameter<Int>.capturing(captor)
    member.addAction(matching: parameter.matches, specificity: parameter.specificity, action: { _ in })
    member.addStub(matching: { _ in true }, outcomes: [.returning(8)])
    #expect(try member.invoke(4) == 8)
    #expect(captor.values == [4])
    #expect(member.verification(matching: { $0 == 4 }, count: 1).success)
    member.reset([.invocations])
    #expect(member.verification(matching: { _ in true }, count: .never).success)
}

@Test func coupledVoidActionEvaluatesMatcherOnceAndResetsByScope() throws {
    let member = MockMember<Int, Void, Void>()
    let captor = ArgumentCaptor<Int>()
    let parameter = Parameter<Int>.capturing(captor)
    var actions = 0
    member.addAction(
        matching: parameter.matches,
        specificity: parameter.specificity,
        outcomes: [.returning(())],
        action: { _ in actions += 1 }
    )

    try member.invoke(1)
    #expect(captor.values == [1])
    #expect(actions == 1)

    member.reset([.actions])
    try member.invoke(2)
    #expect(captor.values == [1, 2])
    #expect(actions == 1)

    member.reset([.stubs])
    #expect(throws: MockError.unstubbed("member")) { try member.invoke(3) }
}

@Test func missingStubThrowsFrameworkError() {
    let member = MockMember<Void, Void, Void>(name: "work")
    #expect(throws: MockError.unstubbed("work")) { try member.invoke(()) }
}

@Test func recordAddsInvocationWithoutNeedingStub() {
    let member = MockMember<Int, Void, Void>(name: "init")
    member.record(42)
    #expect(member.verification(matching: { $0 == 42 }, count: 1).success)
}

@Test func everyCountFormMatchesExpectedInvocations() throws {
    let member = MockMember<Void, Void, Void>()
    member.addStub(matching: { _ in true }, outcomes: [.returning(())])
    try member.invoke(())
    try member.invoke(())

    #expect(member.verification(matching: { _ in true }, count: .exactly(2)).success)
    #expect(member.verification(matching: { _ in true }, count: .atLeast(1)).success)
    #expect(member.verification(matching: { _ in true }, count: .atMost(2)).success)
    #expect(member.verification(matching: { _ in true }, count: .between(1, 3)).success)
    #expect(member.verification(matching: { _ in true }, count: .between(1 ... 2)).success)
    #expect(!member.verification(matching: { _ in true }, count: .never).success)
}

@Test func scopedResetOnlyClearsRequestedState() throws {
    let member = MockMember<Int, Void, Int>()
    var actions = 0
    member.addAction(matching: { _ in true }, action: { _ in actions += 1 })
    member.addStub(matching: { _ in true }, outcomes: [.returning(1)])

    #expect(try member.invoke(1) == 1)
    member.reset([.invocations])
    #expect(member.invocationCount(matching: { _ in true }) == 0)
    #expect(try member.invoke(2) == 1)
    #expect(actions == 2)

    member.reset([.actions])
    #expect(try member.invoke(3) == 1)
    #expect(actions == 2)

    member.reset([.stubs])
    #expect(throws: MockError.unstubbed("member")) { try member.invoke(4) }
}

@Test func staticRegistryReusesTypedMemberAndResetsIt() throws {
    enum Owner {}
    let registry = StaticMockRegistry()
    let first: MockMember<Void, Void, Int> = registry.member(owner: Owner.self, key: "value") { .init(name: "value") }
    first.addStub(matching: { _ in true }, outcomes: [.returning(1)])
    let second: MockMember<Void, Void, Int> = registry.member(owner: Owner.self, key: "value") { .init(name: "other") }
    #expect(first === second)
    #expect(try second.invoke(()) == 1)
    registry.reset(owner: Owner.self, scopes: [.stubs])
    #expect(throws: MockError.unstubbed("value")) { try second.invoke(()) }
}

@Test func staticRegistrySeparatesGenericSpecializations() throws {
    enum Owner {}
    let registry = StaticMockRegistry()
    let strings: MockMember<String, Void, String> = registry.member(owner: Owner.self, key: "echo", types: [String.self]) { .init(name: "echo") }
    let integers: MockMember<Int, Void, Int> = registry.member(owner: Owner.self, key: "echo", types: [Int.self]) { .init(name: "echo") }
    strings.addStub(matching: { _ in true }, outcomes: [.returning("text")])
    integers.addStub(matching: { _ in true }, outcomes: [.returning(1)])
    #expect(try strings.invoke("input") == "text")
    #expect(try integers.invoke(0) == 1)
    registry.reset(owner: Owner.self, scopes: [.stubs])
    #expect(throws: MockError.unstubbed("echo")) { try strings.invoke("input") }
    #expect(throws: MockError.unstubbed("echo")) { try integers.invoke(0) }
}

@Test func genericRegistrySeparatesTypeSpecializations() throws {
    let registry = GenericMockRegistry()
    let strings: MockMember<String, Void, String> = registry.member(key: "echo", types: [String.self]) { .init(name: "echo") }
    let integers: MockMember<Int, Void, Int> = registry.member(key: "echo", types: [Int.self]) { .init(name: "echo") }
    strings.addStub(matching: { _ in true }, outcomes: [.returning("text")])
    integers.addStub(matching: { _ in true }, outcomes: [.returning(1)])
    #expect(try strings.invoke("input") == "text")
    #expect(try integers.invoke(0) == 1)
}

@Test func memberSupportsConcurrentInvocation() async throws {
    let member = MockMember<Int, Void, Int>()
    member.addStub(matching: { _ in true }, outcomes: [.returning(1)])

    try await withThrowingTaskGroup(of: Int.self) { group in
        for value in 0 ..< 100 {
            group.addTask { try member.invoke(value) }
        }
        for try await result in group {
            #expect(result == 1)
        }
    }

    #expect(member.invocationCount(matching: { _ in true }) == 100)
}

@Test func memberSupportsConcurrentConfiguration() async throws {
    let member = MockMember<Int, Void, Int>()

    await withTaskGroup(of: Void.self) { group in
        for value in 0 ..< 100 {
            group.addTask {
                member.addStub(matching: { $0 == value }, specificity: 1, outcomes: [.returning(value)])
            }
        }
    }

    for value in 0 ..< 100 {
        #expect(try member.invoke(value) == value)
    }
}
