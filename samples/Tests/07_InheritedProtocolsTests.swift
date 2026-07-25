import Mock4Swift
import Mock4SwiftTesting
import Testing

protocol InheritedSampleParent {
    var flag: Bool { get set }
    func inherited(_ value: Int) -> String
}

@Mockable
protocol InheritedSampleChild: InheritedSampleParent {
    init(seed: Int)
    func own() -> Int
}

protocol IndexedSampleParent {
    subscript(_ key: String) -> Int { get set }
}

protocol NamedSampleParent {
    func name() -> String
}

typealias CombinedSampleRequirements = IndexedSampleParent & NamedSampleParent

@Mockable
protocol CombinedSampleParents: CombinedSampleRequirements {}

@Test
private func inheritedProtocolGetsTheNormalTypedDSL() {
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
private func compositionAliasesAndSubscriptsUseGeneratedChannels() {
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
