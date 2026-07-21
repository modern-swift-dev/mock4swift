import Foundation

/// Thread-safe collector for argument values matched by a capturing parameter.
public final class ArgumentCaptor<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Value] = []

    public init() {}
    public var values: [Value] { lock.withLock { storage } }
    public var lastValue: Value? { lock.withLock { storage.last } }
    public func reset() { lock.withLock { storage.removeAll() } }
    func append(_ value: Value) { lock.withLock { storage.append(value) } }
}
