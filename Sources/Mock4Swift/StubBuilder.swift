public struct _Mock4SwiftReturnStub<Arguments, Ephemeral, Output, Answer> {
    private let apply: ([StubOutcome<Arguments, Ephemeral, Output>])
        -> _Mock4SwiftStubRegistration<Arguments, Ephemeral, Output>
    private let answerOutcome: (Answer) -> StubOutcome<Arguments, Ephemeral, Output>

    public init(
        apply: @escaping ([StubOutcome<Arguments, Ephemeral, Output>])
            -> _Mock4SwiftStubRegistration<Arguments, Ephemeral, Output>,
        answer: @escaping (Answer) -> StubOutcome<Arguments, Ephemeral, Output>
    ) {
        self.apply = apply
        answerOutcome = answer
    }

    @discardableResult
    public func willReturn(
        _ values: Output...
    ) -> _Mock4SwiftReturnSequence<Arguments, Ephemeral, Output, Answer> {
        .init(registration: apply(values.map(StubOutcome.returning)), answer: answerOutcome)
    }

    @discardableResult
    public func willAnswer(_ answer: Answer) -> _Mock4SwiftReturnSequence<Arguments, Ephemeral, Output, Answer> {
        .init(registration: apply([answerOutcome(answer)]), answer: answerOutcome)
    }

}

public struct _Mock4SwiftReturnSequence<Arguments, Ephemeral, Output, Answer> {
    private let registration: _Mock4SwiftStubRegistration<Arguments, Ephemeral, Output>
    private let answerOutcome: (Answer) -> StubOutcome<Arguments, Ephemeral, Output>

    public init(
        registration: _Mock4SwiftStubRegistration<Arguments, Ephemeral, Output>,
        answer: @escaping (Answer) -> StubOutcome<Arguments, Ephemeral, Output>
    ) {
        self.registration = registration
        answerOutcome = answer
    }

    @discardableResult
    public func thenReturn(_ values: Output...) -> Self {
        registration.append(values.map(StubOutcome.returning))
        return self
    }

    @discardableResult
    public func thenAnswer(_ answer: Answer) -> Self {
        registration.append([answerOutcome(answer)])
        return self
    }

}

public struct _Mock4SwiftThrowingReturnStub<
    Arguments,
    Ephemeral,
    Output,
    Failure: Error,
    Answer
> {
    private let apply: ([StubOutcome<Arguments, Ephemeral, Output>])
        -> _Mock4SwiftStubRegistration<Arguments, Ephemeral, Output>
    private let answerOutcome: (Answer) -> StubOutcome<Arguments, Ephemeral, Output>

    public init(
        apply: @escaping ([StubOutcome<Arguments, Ephemeral, Output>])
            -> _Mock4SwiftStubRegistration<Arguments, Ephemeral, Output>,
        answer: @escaping (Answer) -> StubOutcome<Arguments, Ephemeral, Output>
    ) {
        self.apply = apply
        answerOutcome = answer
    }

    @discardableResult
    public func willReturn(
        _ values: Output...
    ) -> _Mock4SwiftThrowingReturnSequence<Arguments, Ephemeral, Output, Failure, Answer> {
        .init(registration: apply(values.map(StubOutcome.returning)), answer: answerOutcome)
    }

    @discardableResult
    public func willThrow(
        _ errors: Failure...
    ) -> _Mock4SwiftThrowingReturnSequence<Arguments, Ephemeral, Output, Failure, Answer> {
        .init(registration: apply(errors.map(StubOutcome.throwing)), answer: answerOutcome)
    }

    @discardableResult
    public func willAnswer(
        _ answer: Answer
    ) -> _Mock4SwiftThrowingReturnSequence<Arguments, Ephemeral, Output, Failure, Answer> {
        .init(registration: apply([answerOutcome(answer)]), answer: answerOutcome)
    }

}

public struct _Mock4SwiftThrowingReturnSequence<
    Arguments,
    Ephemeral,
    Output,
    Failure: Error,
    Answer
> {
    private let registration: _Mock4SwiftStubRegistration<Arguments, Ephemeral, Output>
    private let answerOutcome: (Answer) -> StubOutcome<Arguments, Ephemeral, Output>

    public init(
        registration: _Mock4SwiftStubRegistration<Arguments, Ephemeral, Output>,
        answer: @escaping (Answer) -> StubOutcome<Arguments, Ephemeral, Output>
    ) {
        self.registration = registration
        answerOutcome = answer
    }

    @discardableResult
    public func thenReturn(_ values: Output...) -> Self {
        registration.append(values.map(StubOutcome.returning))
        return self
    }

    @discardableResult
    public func thenThrow(_ errors: Failure...) -> Self {
        registration.append(errors.map(StubOutcome.throwing))
        return self
    }

    @discardableResult
    public func thenAnswer(_ answer: Answer) -> Self {
        registration.append([answerOutcome(answer)])
        return self
    }

}

public struct _Mock4SwiftProduceStub<
    Arguments: ~Copyable,
    Ephemeral: ~Copyable,
    Output: ~Copyable,
    Answer
> {
    private let apply: ([TransientStubOutcome<Arguments, Ephemeral, Output>])
        -> _Mock4SwiftTransientStubRegistration<Arguments, Ephemeral, Output>
    private let answerOutcome: (Answer) -> TransientStubOutcome<Arguments, Ephemeral, Output>

    public init(
        apply: @escaping ([TransientStubOutcome<Arguments, Ephemeral, Output>])
            -> _Mock4SwiftTransientStubRegistration<Arguments, Ephemeral, Output>,
        answer: @escaping (Answer) -> TransientStubOutcome<Arguments, Ephemeral, Output>
    ) {
        self.apply = apply
        answerOutcome = answer
    }

    @discardableResult
    public func willProduce(
        _ producers: (() -> Output)...
    ) -> _Mock4SwiftProduceSequence<Arguments, Ephemeral, Output, Answer> {
        .init(registration: apply(producers.map(TransientStubOutcome.producing)), answer: answerOutcome)
    }

    @discardableResult
    public func willAnswer(_ answer: Answer) -> _Mock4SwiftProduceSequence<Arguments, Ephemeral, Output, Answer> {
        .init(registration: apply([answerOutcome(answer)]), answer: answerOutcome)
    }
}

public struct _Mock4SwiftProduceSequence<
    Arguments: ~Copyable,
    Ephemeral: ~Copyable,
    Output: ~Copyable,
    Answer
> {
    private let registration: _Mock4SwiftTransientStubRegistration<Arguments, Ephemeral, Output>
    private let answerOutcome: (Answer) -> TransientStubOutcome<Arguments, Ephemeral, Output>

    public init(
        registration: _Mock4SwiftTransientStubRegistration<Arguments, Ephemeral, Output>,
        answer: @escaping (Answer) -> TransientStubOutcome<Arguments, Ephemeral, Output>
    ) {
        self.registration = registration
        answerOutcome = answer
    }

    @discardableResult
    public func thenProduce(_ producers: (() -> Output)...) -> Self {
        registration.append(producers.map(TransientStubOutcome.producing))
        return self
    }

    @discardableResult
    public func thenAnswer(_ answer: Answer) -> Self {
        registration.append([answerOutcome(answer)])
        return self
    }
}

public struct _Mock4SwiftThrowingProduceStub<
    Arguments: ~Copyable,
    Ephemeral: ~Copyable,
    Output: ~Copyable,
    Failure: Error,
    Answer
> {
    private let apply: ([TransientStubOutcome<Arguments, Ephemeral, Output>])
        -> _Mock4SwiftTransientStubRegistration<Arguments, Ephemeral, Output>
    private let answerOutcome: (Answer) -> TransientStubOutcome<Arguments, Ephemeral, Output>

    public init(
        apply: @escaping ([TransientStubOutcome<Arguments, Ephemeral, Output>])
            -> _Mock4SwiftTransientStubRegistration<Arguments, Ephemeral, Output>,
        answer: @escaping (Answer) -> TransientStubOutcome<Arguments, Ephemeral, Output>
    ) {
        self.apply = apply
        answerOutcome = answer
    }

    @discardableResult
    public func willProduce(
        _ producers: (() -> Output)...
    ) -> _Mock4SwiftThrowingProduceSequence<Arguments, Ephemeral, Output, Failure, Answer> {
        .init(registration: apply(producers.map(TransientStubOutcome.producing)), answer: answerOutcome)
    }

    @discardableResult
    public func willThrow(
        _ errors: Failure...
    ) -> _Mock4SwiftThrowingProduceSequence<Arguments, Ephemeral, Output, Failure, Answer> {
        .init(registration: apply(errors.map(TransientStubOutcome.throwing)), answer: answerOutcome)
    }

    @discardableResult
    public func willAnswer(
        _ answer: Answer
    ) -> _Mock4SwiftThrowingProduceSequence<Arguments, Ephemeral, Output, Failure, Answer> {
        .init(registration: apply([answerOutcome(answer)]), answer: answerOutcome)
    }
}

public struct _Mock4SwiftThrowingProduceSequence<
    Arguments: ~Copyable,
    Ephemeral: ~Copyable,
    Output: ~Copyable,
    Failure: Error,
    Answer
> {
    private let registration: _Mock4SwiftTransientStubRegistration<Arguments, Ephemeral, Output>
    private let answerOutcome: (Answer) -> TransientStubOutcome<Arguments, Ephemeral, Output>

    public init(
        registration: _Mock4SwiftTransientStubRegistration<Arguments, Ephemeral, Output>,
        answer: @escaping (Answer) -> TransientStubOutcome<Arguments, Ephemeral, Output>
    ) {
        self.registration = registration
        answerOutcome = answer
    }

    @discardableResult
    public func thenProduce(_ producers: (() -> Output)...) -> Self {
        registration.append(producers.map(TransientStubOutcome.producing))
        return self
    }

    @discardableResult
    public func thenThrow(_ errors: Failure...) -> Self {
        registration.append(errors.map(TransientStubOutcome.throwing))
        return self
    }

    @discardableResult
    public func thenAnswer(_ answer: Answer) -> Self {
        registration.append([answerOutcome(answer)])
        return self
    }
}

public struct _Mock4SwiftThrowingVoidStub<
    Arguments,
    Ephemeral,
    Failure: Error,
    Answer
> {
    private let apply: ([StubOutcome<Arguments, Ephemeral, Void>])
        -> _Mock4SwiftStubRegistration<Arguments, Ephemeral, Void>
    private let answerOutcome: (Answer) -> StubOutcome<Arguments, Ephemeral, Void>

    public init(
        apply: @escaping ([StubOutcome<Arguments, Ephemeral, Void>])
            -> _Mock4SwiftStubRegistration<Arguments, Ephemeral, Void>,
        answer: @escaping (Answer) -> StubOutcome<Arguments, Ephemeral, Void>
    ) {
        self.apply = apply
        answerOutcome = answer
    }

    @discardableResult
    public func willSucceed() -> _Mock4SwiftThrowingVoidSequence<Arguments, Ephemeral, Failure, Answer> {
        .init(registration: apply([.returning(())]), answer: answerOutcome)
    }

    @discardableResult
    public func willThrow(
        _ errors: Failure...
    ) -> _Mock4SwiftThrowingVoidSequence<Arguments, Ephemeral, Failure, Answer> {
        .init(registration: apply(errors.map(StubOutcome.throwing)), answer: answerOutcome)
    }

    @discardableResult
    public func willAnswer(
        _ answer: Answer
    ) -> _Mock4SwiftThrowingVoidSequence<Arguments, Ephemeral, Failure, Answer> {
        .init(registration: apply([answerOutcome(answer)]), answer: answerOutcome)
    }
}

public struct _Mock4SwiftThrowingVoidSequence<
    Arguments,
    Ephemeral,
    Failure: Error,
    Answer
> {
    private let registration: _Mock4SwiftStubRegistration<Arguments, Ephemeral, Void>
    private let answerOutcome: (Answer) -> StubOutcome<Arguments, Ephemeral, Void>

    public init(
        registration: _Mock4SwiftStubRegistration<Arguments, Ephemeral, Void>,
        answer: @escaping (Answer) -> StubOutcome<Arguments, Ephemeral, Void>
    ) {
        self.registration = registration
        answerOutcome = answer
    }

    @discardableResult
    public func thenSucceed() -> Self {
        registration.append([.returning(())])
        return self
    }

    @discardableResult
    public func thenThrow(_ errors: Failure...) -> Self {
        registration.append(errors.map(StubOutcome.throwing))
        return self
    }

    @discardableResult
    public func thenAnswer(_ answer: Answer) -> Self {
        registration.append([answerOutcome(answer)])
        return self
    }
}

public struct _Mock4SwiftThrowingProduceVoidStub<
    Arguments: ~Copyable,
    Ephemeral: ~Copyable,
    Failure: Error,
    Answer
> {
    private let apply: ([TransientStubOutcome<Arguments, Ephemeral, Void>])
        -> _Mock4SwiftTransientStubRegistration<Arguments, Ephemeral, Void>
    private let answerOutcome: (Answer) -> TransientStubOutcome<Arguments, Ephemeral, Void>

    public init(
        apply: @escaping ([TransientStubOutcome<Arguments, Ephemeral, Void>])
            -> _Mock4SwiftTransientStubRegistration<Arguments, Ephemeral, Void>,
        answer: @escaping (Answer) -> TransientStubOutcome<Arguments, Ephemeral, Void>
    ) {
        self.apply = apply
        answerOutcome = answer
    }

    @discardableResult
    public func willSucceed() -> _Mock4SwiftThrowingProduceVoidSequence<Arguments, Ephemeral, Failure, Answer> {
        .init(registration: apply([.producing { () }]), answer: answerOutcome)
    }

    @discardableResult
    public func willThrow(
        _ errors: Failure...
    ) -> _Mock4SwiftThrowingProduceVoidSequence<Arguments, Ephemeral, Failure, Answer> {
        .init(registration: apply(errors.map(TransientStubOutcome.throwing)), answer: answerOutcome)
    }

    @discardableResult
    public func willAnswer(
        _ answer: Answer
    ) -> _Mock4SwiftThrowingProduceVoidSequence<Arguments, Ephemeral, Failure, Answer> {
        .init(registration: apply([answerOutcome(answer)]), answer: answerOutcome)
    }
}

public struct _Mock4SwiftThrowingProduceVoidSequence<
    Arguments: ~Copyable,
    Ephemeral: ~Copyable,
    Failure: Error,
    Answer
> {
    private let registration: _Mock4SwiftTransientStubRegistration<Arguments, Ephemeral, Void>
    private let answerOutcome: (Answer) -> TransientStubOutcome<Arguments, Ephemeral, Void>

    public init(
        registration: _Mock4SwiftTransientStubRegistration<Arguments, Ephemeral, Void>,
        answer: @escaping (Answer) -> TransientStubOutcome<Arguments, Ephemeral, Void>
    ) {
        self.registration = registration
        answerOutcome = answer
    }

    @discardableResult
    public func thenSucceed() -> Self {
        registration.append([.producing { () }])
        return self
    }

    @discardableResult
    public func thenThrow(_ errors: Failure...) -> Self {
        registration.append(errors.map(TransientStubOutcome.throwing))
        return self
    }

    @discardableResult
    public func thenAnswer(_ answer: Answer) -> Self {
        registration.append([answerOutcome(answer)])
        return self
    }
}
