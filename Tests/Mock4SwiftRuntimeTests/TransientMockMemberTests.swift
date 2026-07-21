import Mock4Swift
import Testing

@Test func transientMemberUsesSpecificNewestProducerAndRepeatsLast() throws {
    let member = TransientMockMember<Int, Int>(name: "transient")
    member.addStub(matching: { _ in true }, outcomes: [.producing { 1 }])
    member.addStub(matching: { $0 == 1 }, specificity: 1, outcomes: [.producing { 2 }, .producing { 3 }])
    member.addStub(matching: { $0 == 1 }, specificity: 1, outcomes: [.producing { 4 }])

    #expect(try member.invoke(1) == 4)
    #expect(try member.invoke(2) == 1)
    #expect(try member.invoke(1) == 4)
}

@Test func transientMemberRepeatsSelectedProducerSequence() throws {
    let member = TransientMockMember<Int, Int>()
    member.addStub(matching: { _ in true }, outcomes: [.producing { 1 }])
    member.addStub(matching: { $0 == 1 }, specificity: 1, outcomes: [.producing { 2 }, .producing { 3 }])

    #expect(try member.invoke(1) == 2)
    #expect(try member.invoke(1) == 3)
    #expect(try member.invoke(1) == 3)
}

@Test func transientMemberSupportsNoncopyableArgumentsAndResults() throws {
    struct Token: ~Copyable { let value: Int }
    let member = TransientMockMember<Token, Token>(name: "token")
    member.addStub(matching: { _ in true }, outcomes: [.producing { Token(value: 7) }])

    let result = try member.invoke(Token(value: 1))
    #expect(result.value == 7)
    #expect(member.verification(count: 1).success)
}

@Test func transientMemberIsCountOnlyAndResetsByScope() throws {
    let member = TransientMockMember<Int, Int>(name: "count")
    var actions = 0
    member.addAction(matching: { _ in true }, action: { _ in actions += 1 })
    member.addStub(matching: { _ in true }, outcomes: [.producing { 8 }])

    #expect(try member.invoke(1) == 8)
    #expect(member.verification(count: .exactly(1)).success)
    member.reset([.invocations])
    #expect(member.verification(count: .never).success)
    #expect(try member.invoke(2) == 8)
    member.reset([.actions])
    #expect(try member.invoke(3) == 8)
    #expect(actions == 2)
    member.reset([.stubs])
    #expect(throws: MockError.unstubbed("count")) { try member.invoke(4) }
}

@Test func transientCoupledVoidActionMatchesOnceAndResetsByScope() throws {
    let member = TransientMockMember<Int, Void>()
    var matches = 0
    var actions = 0
    member.addAction(
        matching: { _ in matches += 1; return true },
        outcomes: [.producing { () }],
        action: { _ in actions += 1 }
    )

    try member.invoke(1)
    #expect(matches == 1)
    #expect(actions == 1)

    member.reset([.actions])
    try member.invoke(2)
    #expect(matches == 2)
    #expect(actions == 1)

    member.reset([.stubs])
    #expect(throws: MockError.unstubbed("member")) { try member.invoke(3) }
    #expect(matches == 2)
}

@Test func transientCallbacksCanReenterChannel() throws {
    let member = TransientMockMember<Int, Int>()
    member.addAction(
        matching: { _ in member.verification(count: 1).success },
        outcomes: [.producing { member.verification(count: 1).success ? 7 : 0 }],
        action: { _ in member.reset([.actions]) }
    )

    #expect(try member.invoke(1) == 7)
    member.reset([.stubs])
}

@Test func transientMemberDoesNotRetainInvocations() throws {
    final class Probe {}
    let member = TransientMockMember<Probe, Void>()
    member.addStub(matching: { _ in true }, outcomes: [.producing { () }])
    weak var retained: Probe?
    do {
        let probe = Probe()
        retained = probe
        try member.invoke(probe)
    }
    #expect(retained == nil)
}

@Test func transientMemberRepeatsFinalThrownOutcome() throws {
    enum Failure: Error { case expected }
    let member = TransientMockMember<Void, Int>()
    member.addStub(matching: { _ in true }, outcomes: [.producing { 1 }, .throwing(Failure.expected)])

    #expect(try member.invoke(()) == 1)
    #expect(throws: Failure.expected) { try member.invoke(()) }
    #expect(throws: Failure.expected) { try member.invoke(()) }
}

@Test func transientRegistriesSeparateSpecializationsAndReset() throws {
    enum Owner {}
    let staticRegistry = StaticMockRegistry()
    let genericRegistry = GenericMockRegistry()
    let strings: TransientMockMember<String, String> = staticRegistry.member(owner: Owner.self, key: "echo", types: [String.self]) { .init(name: "echo") }
    let integers: TransientMockMember<Int, Int> = genericRegistry.member(key: "echo", types: [Int.self]) { .init(name: "echo") }
    strings.addStub(matching: { _ in true }, outcomes: [.producing { "text" }])
    integers.addStub(matching: { _ in true }, outcomes: [.producing { 1 }])

    #expect(try strings.invoke("input") == "text")
    #expect(try integers.invoke(0) == 1)
    staticRegistry.reset(owner: Owner.self, scopes: [.stubs])
    genericRegistry.reset([.stubs])
    #expect(throws: MockError.unstubbed("echo")) { try strings.invoke("input") }
    #expect(throws: MockError.unstubbed("echo")) { try integers.invoke(0) }
}

@Test func transientRegistryKeysNoncopyableGenericSpecializationsByMetatypeIdentifier() throws {
    struct First: ~Copyable {}
    struct Second: ~Copyable {}
    let registry = GenericMockRegistry()

    func member<Value: ~Copyable>(for _: Value.Type) -> TransientMockMember<Value, Int> {
        registry.member(key: "generic", typeIDs: [ObjectIdentifier(Value.self)]) { .init(name: "generic") }
    }

    let first = member(for: First.self)
    let second = member(for: Second.self)
    first.addStub(matching: { _ in true }, outcomes: [.producing { 1 }])
    second.addStub(matching: { _ in true }, outcomes: [.producing { 2 }])
    #expect(try first.invoke(First()) == 1)
    #expect(try second.invoke(Second()) == 2)
}

@Test func transientStaticRegistryReleasesRemovedChannel() {
    enum Owner {}
    let registry = StaticMockRegistry()
    weak var retained: AnyObject?
    do {
        let member: TransientMockMember<Int, Int> = registry.member(owner: Owner.self, key: "value") { .init() }
        retained = member
    }
    registry.remove(owner: Owner.self, key: "value")
    #expect(retained == nil)
}

@Test func transientMemberSupportsConcurrentCalls() async throws {
    let member = TransientMockMember<Int, Int>()
    member.addStub(matching: { _ in true }, outcomes: [.producing { 1 }])

    try await withThrowingTaskGroup(of: Int.self) { group in
        for value in 0..<100 {
            group.addTask { try member.invoke(value) }
        }
        for try await result in group { #expect(result == 1) }
    }
    #expect(member.invocationCount == 100)
}

@Test func transientMemberSupportsConcurrentConfiguration() async throws {
    let member = TransientMockMember<Int, Int>()
    await withTaskGroup(of: Void.self) { group in
        for value in 0..<100 {
            group.addTask {
                member.addStub(matching: { $0 == value }, specificity: 1, outcomes: [.producing { value }])
            }
        }
    }
    for value in 0..<100 { #expect(try member.invoke(value) == value) }
}

@Test func ephemeralDispatcherForwardsNonescapingClosureWithoutRecordingOrRetainingIt() throws {
    protocol Service { func call(id: Int, completion: () -> Void) -> Int }
    final class ServiceMock: Service {
        let member = MockMember<Int, Int>(name: "call")
        let dispatcher = EphemeralActionDispatcher<Int, () -> Void>()

        func call(id: Int, completion: () -> Void) -> Int {
            withoutActuallyEscaping(completion) {
                dispatcher.dispatch(id, ephemeral: $0)
            }
            return try! member.invoke(id)
        }
    }
    final class Probe {}

    let mock = ServiceMock()
    mock.member.addStub(matching: { $0 == 1 }, specificity: 1, outcomes: [.returning(7)])
    var selected: [Int] = []
    mock.dispatcher.addAction(matching: { _ in true }) { _, completion in selected.append(1); completion() }
    mock.dispatcher.addAction(matching: { $0 == 1 }, specificity: 1) { _, completion in selected.append(2); completion() }
    mock.dispatcher.addAction(matching: { $0 == 1 }, specificity: 1) { _, completion in selected.append(3); completion() }

    weak var retained: Probe?
    do {
        let probe = Probe()
        retained = probe
        #expect(mock.call(id: 1) { _ = probe } == 7)
    }
    #expect(selected == [3])
    #expect(retained == nil)
    #expect(mock.member.verification(matching: { $0 == 1 }, count: 1).success)

    mock.dispatcher.reset([.invocations])
    mock.dispatcher.dispatch(1, ephemeral: {})
    #expect(selected == [3, 3])
    mock.dispatcher.reset([.actions])
    mock.dispatcher.dispatch(1, ephemeral: {})
    #expect(selected == [3, 3])
}

@Test func ephemeralDispatcherRegistriesSeparateSpecializationsAndReset() {
    enum Owner {}
    let staticRegistry = StaticMockRegistry()
    let genericRegistry = GenericMockRegistry()
    let strings: EphemeralActionDispatcher<Void, () -> Void> = staticRegistry.member(
        owner: Owner.self, key: "callback", types: [String.self]
    ) { .init() }
    let integers: EphemeralActionDispatcher<Void, () -> Void> = staticRegistry.member(
        owner: Owner.self, key: "callback", types: [Int.self]
    ) { .init() }
    let generic: EphemeralActionDispatcher<Int, () -> Void> = genericRegistry.member(
        key: "callback", types: [Double.self]
    ) { .init() }
    var values: [String] = []
    strings.addAction(matching: { _ in true }) { _, _ in values.append("string") }
    integers.addAction(matching: { _ in true }) { _, _ in values.append("integer") }
    generic.addAction(matching: { $0 == 1 }) { _, _ in values.append("generic") }

    strings.dispatch((), ephemeral: {})
    integers.dispatch((), ephemeral: {})
    generic.dispatch(1, ephemeral: {})
    #expect(values == ["string", "integer", "generic"])

    staticRegistry.reset(owner: Owner.self, scopes: [.actions])
    genericRegistry.reset([.actions])
    strings.dispatch((), ephemeral: {})
    integers.dispatch((), ephemeral: {})
    generic.dispatch(1, ephemeral: {})
    #expect(values == ["string", "integer", "generic"])
}
