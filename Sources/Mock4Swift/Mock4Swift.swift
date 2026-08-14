import Foundation

@attached(peer, names: suffixed(Mock))
public macro Mockable() = #externalMacro(module: "Mock4SwiftMacros", type: "MockableMacro")

/// Implementation detail used by `Mock4SwiftBuildPlugin`.
public enum _Mock4SwiftAccess {
    case `internal`
    case package
    case `public`
}

/// Marks a requirement whose named argument or result types are noncopyable.
/// Generated mocks use a transient, count-only channel for the requirement.
@attached(peer, names: arbitrary)
public macro MockNoncopyable() = #externalMacro(module: "Mock4SwiftMacros", type: "MockNoncopyableMacro")

public func Given<M: Mock>(_ mock: M) -> M.Given {
    mock.given()
}

public func Given<M: StaticMock>(_ type: M.Type) -> M.StaticGiven {
    type.given()
}

public func Calls<M: _Mock4SwiftCallInspectable>(_ mock: M) -> M.Calls {
    mock._mock4SwiftCalls()
}

public func Calls<M: _Mock4SwiftStaticCallInspectable>(_ type: M.Type) -> M.StaticCalls {
    type._mock4SwiftStaticCalls()
}

public func MockState<M: _Mock4SwiftStateControllable>(_ mock: M) -> M.MockState {
    mock._mock4SwiftState()
}

public func MockState<M: _Mock4SwiftStaticStateControllable>(_ type: M.Type) -> M.StaticMockState {
    type._mock4SwiftStaticState()
}

public func Perform<M: Mock>(_ mock: M) -> M.Perform {
    mock.perform()
}

public func Perform<M: StaticMock>(_ type: M.Type) -> M.StaticPerform {
    type.perform()
}

public func resetMock(_ mock: some Mock, scopes: [MockScope] = Array(MockScope.all)) {
    for scope in scopes {
        mock.resetMock(scope)
    }
}

public func resetMock(_ type: (some StaticMock).Type, scopes: [MockScope] = Array(MockScope.all)) {
    for scope in scopes {
        type.resetMock(scope)
    }
}
