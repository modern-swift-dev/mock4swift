import Mock4Swift
import Testing

private enum StateFailure: Error, Equatable {
    case unavailable
}

@Test func nonthrowingPropertyStateStoresMutableValues() {
    let state = MockPropertyState<Int, Never>(initial: 1)

    #expect(state.value == 1)
    state.value = 2
    #expect(state.value == 2)
    state.succeed(with: 3)
    #expect(state.value == 3)
}

@Test func throwingPropertyStateStoresTypedResults() throws {
    let state = MockPropertyState<Int, StateFailure>(initial: .failure(.unavailable))

    #expect(throws: StateFailure.unavailable) { try state.get() }
    state.succeed(with: 4)
    #expect(try state.get() == 4)
    state.fail(with: .unavailable)
    #expect(state.result == .failure(.unavailable))
}
