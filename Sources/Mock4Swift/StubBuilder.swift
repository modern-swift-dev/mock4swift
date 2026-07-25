public struct _Mock4SwiftReturnStub<Output> {
    private let apply: ([Output]) -> Void

    public init(_ apply: @escaping ([Output]) -> Void) {
        self.apply = apply
    }

    public func willReturn(_ values: Output...) {
        apply(values)
    }
}

public struct _Mock4SwiftThrowingReturnStub<Output, Failure: Error> {
    private let applyReturn: ([Output]) -> _Mock4SwiftStubRegistration<Output>
    private let applyThrow: ([Failure]) -> _Mock4SwiftStubRegistration<Output>

    public init(
        willReturn: @escaping ([Output]) -> _Mock4SwiftStubRegistration<Output>,
        willThrow: @escaping ([Failure]) -> _Mock4SwiftStubRegistration<Output>
    ) {
        applyReturn = willReturn
        applyThrow = willThrow
    }

    @discardableResult
    public func willReturn(_ values: Output...) -> _Mock4SwiftThrowingReturnSequence<Output, Failure> {
        .init(registration: applyReturn(values))
    }

    @discardableResult
    public func willThrow(_ errors: Failure...) -> _Mock4SwiftThrowingReturnSequence<Output, Failure> {
        .init(registration: applyThrow(errors))
    }
}

public struct _Mock4SwiftThrowingReturnSequence<Output, Failure: Error> {
    private let registration: _Mock4SwiftStubRegistration<Output>

    public init(registration: _Mock4SwiftStubRegistration<Output>) {
        self.registration = registration
    }

    @discardableResult
    public func thenReturn(_ values: Output...) -> Self {
        registration.append(values.map(StubOutcome.returnValue))
        return self
    }

    @discardableResult
    public func thenThrow(_ errors: Failure...) -> Self {
        registration.append(errors.map(StubOutcome.throwError))
        return self
    }
}

public struct _Mock4SwiftProduceStub<Output: ~Copyable> {
    private let apply: ([() -> Output]) -> Void

    public init(_ apply: @escaping ([() -> Output]) -> Void) {
        self.apply = apply
    }

    public func willProduce(_ producers: (() -> Output)...) {
        apply(producers)
    }
}

public struct _Mock4SwiftThrowingProduceStub<Output: ~Copyable, Failure: Error> {
    private let applyProduce: ([() -> Output]) -> _Mock4SwiftTransientStubRegistration<Output>
    private let applyThrow: ([Failure]) -> _Mock4SwiftTransientStubRegistration<Output>

    public init(
        willProduce: @escaping ([() -> Output]) -> _Mock4SwiftTransientStubRegistration<Output>,
        willThrow: @escaping ([Failure]) -> _Mock4SwiftTransientStubRegistration<Output>
    ) {
        applyProduce = willProduce
        applyThrow = willThrow
    }

    @discardableResult
    public func willProduce(_ producers: (() -> Output)...) -> _Mock4SwiftThrowingProduceSequence<Output, Failure> {
        .init(registration: applyProduce(producers))
    }

    @discardableResult
    public func willThrow(_ errors: Failure...) -> _Mock4SwiftThrowingProduceSequence<Output, Failure> {
        .init(registration: applyThrow(errors))
    }
}

public struct _Mock4SwiftThrowingProduceSequence<Output: ~Copyable, Failure: Error> {
    private let registration: _Mock4SwiftTransientStubRegistration<Output>

    public init(registration: _Mock4SwiftTransientStubRegistration<Output>) {
        self.registration = registration
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
}

public struct _Mock4SwiftThrowingVoidStub<Failure: Error> {
    private let applySuccess: () -> _Mock4SwiftThrowingVoidSequence<Failure>
    private let applyThrow: ([Failure]) -> _Mock4SwiftThrowingVoidSequence<Failure>

    public init(
        willSucceed: @escaping () -> _Mock4SwiftThrowingVoidSequence<Failure>,
        willThrow: @escaping ([Failure]) -> _Mock4SwiftThrowingVoidSequence<Failure>
    ) {
        applySuccess = willSucceed
        applyThrow = willThrow
    }

    @discardableResult
    public func willSucceed() -> _Mock4SwiftThrowingVoidSequence<Failure> {
        applySuccess()
    }

    @discardableResult
    public func willThrow(_ errors: Failure...) -> _Mock4SwiftThrowingVoidSequence<Failure> {
        applyThrow(errors)
    }
}

public struct _Mock4SwiftThrowingVoidSequence<Failure: Error> {
    private let appendSuccess: () -> Void
    private let appendThrow: ([Failure]) -> Void

    public init(
        thenSucceed: @escaping () -> Void,
        thenThrow: @escaping ([Failure]) -> Void
    ) {
        appendSuccess = thenSucceed
        appendThrow = thenThrow
    }

    @discardableResult
    public func thenSucceed() -> Self {
        appendSuccess()
        return self
    }

    @discardableResult
    public func thenThrow(_ errors: Failure...) -> Self {
        precondition(!errors.isEmpty, "Mock stub sequence additions need at least one outcome")
        appendThrow(errors)
        return self
    }
}
