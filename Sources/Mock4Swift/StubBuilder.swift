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
    private let applyReturn: ([Output]) -> Void
    private let applyThrow: ([Failure]) -> Void

    public init(
        willReturn: @escaping ([Output]) -> Void,
        willThrow: @escaping ([Failure]) -> Void
    ) {
        applyReturn = willReturn
        applyThrow = willThrow
    }

    public func willReturn(_ values: Output...) {
        applyReturn(values)
    }

    public func willThrow(_ errors: Failure...) {
        applyThrow(errors)
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
    private let applyProduce: ([() -> Output]) -> Void
    private let applyThrow: ([Failure]) -> Void

    public init(
        willProduce: @escaping ([() -> Output]) -> Void,
        willThrow: @escaping ([Failure]) -> Void
    ) {
        applyProduce = willProduce
        applyThrow = willThrow
    }

    public func willProduce(_ producers: (() -> Output)...) {
        applyProduce(producers)
    }

    public func willThrow(_ errors: Failure...) {
        applyThrow(errors)
    }
}

public struct _Mock4SwiftThrowingVoidStub<Failure: Error> {
    private let apply: ([Failure]) -> Void

    public init(_ apply: @escaping ([Failure]) -> Void) {
        self.apply = apply
    }

    public func willThrow(_ errors: Failure...) {
        apply(errors)
    }
}
