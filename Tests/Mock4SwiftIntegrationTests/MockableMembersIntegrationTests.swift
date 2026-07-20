import Mock4Swift
import Mock4SwiftTesting
import Testing

public protocol InheritedParent {
    func inherited(_ value: Int) -> String
    var flag: Bool { get set }
}

public protocol InheritedChild: InheritedParent {
    func own() -> Int
}

@MockableMembers
public final class InheritedChildMock: InheritedChild {
    public init(seed: Int)
    public func inherited(_ value: Int) -> String
    public var flag: Bool
    public func own() -> Int
}

@Test
private func handwrittenInheritedMockUsesGeneratedRuntimeSupport() {
    let mock = InheritedChildMock(seed: 3)

    Given(mock, .inherited(.value(1), willReturn: "one"))
    Given(mock, .flag(willReturn: true))
    Given(mock, .flag(set: .any))
    Given(mock, .own(willReturn: 2))

    #expect(mock.inherited(1) == "one")
    #expect(mock.flag)
    mock.flag = false
    #expect(mock.own() == 2)

    Verify(mock, 1, .inherited(.value(1)))
    Verify(mock, 1, .flag())
    Verify(mock, 1, .flag(set: .value(false)))
    Verify(mock, 1, .own())
    Verify(mock, 1, .initializer(seed: .value(3)))
}

@MainActor
private protocol MainActorInherited {
    func value() -> Int
}

@MockableMembers
@MainActor
private final class MainActorInheritedMock: MainActorInherited {
    func value() -> Int
}

@Test @MainActor
private func globalActorHandwrittenMockKeepsConfigurationNonisolated() {
    let mock = MainActorInheritedMock()
    Given(mock, .value(willReturn: 4))
    #expect(mock.value() == 4)
    Verify(mock, 1, .value())
}

private protocol ActorInherited: Actor {
    func value() -> Int
}

@MockableMembers
private actor ActorInheritedMock: ActorInherited {
    func value() -> Int
}

@Test
private func actorHandwrittenMockKeepsConfigurationNonisolated() async {
    let mock = ActorInheritedMock()
    Given(mock, .value(willReturn: 5))
    #expect(await mock.value() == 5)
    Verify(mock, 1, .value())
}
