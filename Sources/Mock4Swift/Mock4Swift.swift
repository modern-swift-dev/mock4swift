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

public func Given<M: Mock>(_ mock: M, _ configuration: M.Given) {
    mock.given(configuration)
}

public func Given<M: StaticMock>(_ type: M.Type, _ configuration: M.StaticGiven) {
    type.given(configuration)
}

public func Perform<M: Mock>(_ mock: M, _ configuration: M.Perform) {
    mock.perform(configuration)
}

public func Perform<M: StaticMock>(_ type: M.Type, _ configuration: M.StaticPerform) {
    type.perform(configuration)
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
