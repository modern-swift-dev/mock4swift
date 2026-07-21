import Mock4Swift
import Mock4SwiftTesting
import Testing

private protocol InheritedSampleParent {
    var flag: Bool { get set }
    func inherited(_ value: Int) -> String
}

private protocol InheritedSampleChild: InheritedSampleParent {
    func own() -> Int
}

// Peer macros cannot inspect requirements inherited from another custom
// protocol. Declare the complete witness surface on a final class and attach
// @MockableMembers instead. Bodies and mocking support are generated in place.
@MockableMembers
private final class InheritedSampleChildMock: InheritedSampleChild {
    init(seed: Int)
    var flag: Bool
    func inherited(_ value: Int) -> String
    func own() -> Int
}

private protocol IndexedSampleParent {
    subscript(_ key: String) -> Int { get set }
}

private protocol NamedSampleParent {
    func name() -> String
}

private typealias CombinedSampleParents = IndexedSampleParent & NamedSampleParent

@MockableMembers
private final class CombinedSampleParentsMock: CombinedSampleParents {
    // Swift rejects a bodyless class subscript before the attached macro can
    // synthesize it. #MockableAccessor is the explicit accessor escape hatch.
    subscript(_ key: String) -> Int {
        get { #MockableAccessor() }
        set { #MockableAccessor() as Void }
    }

    func name() -> String
}

@Test
private func handwrittenInheritedMockGetsTheNormalTypedDSL() {
    let child = InheritedSampleChildMock(seed: 3)

    // After declaration, usage is identical to a direct @Mockable protocol.
    Given(child, .inherited(.value(1), willReturn: "one"))
    Given(child, .flag(willReturn: true))
    Given(child, .flag(set: .any))
    Given(child, .own(willReturn: 2))

    #expect(child.inherited(1) == "one")
    #expect(child.flag)
    child.flag = false
    #expect(child.own() == 2)

    Verify(child, 1, .inherited(.value(1)))
    Verify(child, 1, .flag())
    Verify(child, 1, .flag(set: .value(false)))
    Verify(child, 1, .own())
    Verify(child, 1, .initializer(seed: .value(3)))
}

@Test
private func compositionAliasesAndExplicitAccessorsUseGeneratedChannels() {
    let combined = CombinedSampleParentsMock()

    Given(combined, .subscriptGet(.value("key"), willReturn: 1))
    Given(combined, .subscriptSet(.value("key"), value: .value(2)))
    Given(combined, .name(willReturn: "combined"))

    #expect(combined["key"] == 1)
    combined["key"] = 2
    #expect(combined.name() == "combined")

    Verify(combined, 1, .subscriptGet(.value("key")))
    Verify(combined, 1, .subscriptSet(.value("key"), value: .value(2)))
    Verify(combined, 1, .name())
}
