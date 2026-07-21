import Foundation

@attached(peer, names: suffixed(Mock))
public macro Mockable() = #externalMacro(module: "Mock4SwiftMacros", type: "MockableMacro")

@attached(member, names: arbitrary)
@attached(memberAttribute)
@attached(extension, conformances: Mock, StaticMock)
public macro MockableMembers() = #externalMacro(module: "Mock4SwiftMacros", type: "MockableMembersMacro")

/// Marks a requirement whose named argument or result types are noncopyable.
/// Generated mocks use a transient, count-only channel for the requirement.
@attached(peer, names: arbitrary)
public macro MockNoncopyable() = #externalMacro(module: "Mock4SwiftMacros", type: "MockNoncopyableMacro")

/// Synthesizes an inherited subscript accessor declared in a handwritten
/// `@MockableMembers` mock. Invoke it as the accessor's only expression.
@freestanding(expression)
public macro MockableAccessor<Value>() -> Value = #externalMacro(module: "Mock4SwiftMacros", type: "MockableExplicitAccessorMacro")

/// Implementation detail used by `@MockableMembers`; do not apply directly.
@attached(body)
public macro _Mock4SwiftBody(_ index: Int) = #externalMacro(module: "Mock4SwiftMacros", type: "MockableBodyMacro")

/// Implementation detail used by `@MockableMembers`; do not apply directly.
@attached(accessor)
public macro _Mock4SwiftAccessor(_ index: Int) = #externalMacro(module: "Mock4SwiftMacros", type: "MockableAccessorMacro")

public func Given<M: Mock>(_ mock: M, _ configuration: M.Given) { mock.given(configuration) }
public func Given<M: StaticMock>(_ type: M.Type, _ configuration: M.StaticGiven) { type.given(configuration) }
public func Perform<M: Mock>(_ mock: M, _ configuration: M.Perform) { mock.perform(configuration) }
public func Perform<M: StaticMock>(_ type: M.Type, _ configuration: M.StaticPerform) { type.perform(configuration) }
public func resetMock<M: Mock>(_ mock: M, scopes: [MockScope] = Array(MockScope.all)) {
    for scope in scopes { mock.resetMock(scope) }
}
public func resetMock<M: StaticMock>(_ type: M.Type, scopes: [MockScope] = Array(MockScope.all)) {
    for scope in scopes { type.resetMock(scope) }
}
