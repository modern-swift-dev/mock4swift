import Mock4Swift
import Mock4SwiftTesting
import Testing

@Mockable
private protocol WeatherService {
    var unit: String { get set }

    func temperature(for city: String) async throws -> Double
    func save(_ value: Int)
    func greeting() -> String
}

@Mockable
private protocol AdvancedService {
    init(seed: Int)

    static var sharedValue: Int { get set }
    static func make(_ value: Int) -> String

    subscript(_ key: String) -> Int { get set }
}

@Mockable
private protocol Repository {
    associatedtype Item: Equatable

    func load() -> Item
    func convert(_ value: Int) -> String
    func convert(_ value: String) -> Int
    func total(_ values: Int...) -> Int
    func mutate(_ value: inout Int)
}

@Mockable
private protocol Worker: Actor {
    func work(_ value: Int) -> String
}

private enum LoadFailure: Error, Equatable {
    case unavailable
}

@Mockable
private protocol TypedThrower {
    func load(_ key: String) throws(LoadFailure) -> Int
}

@Mockable
private protocol GenericService {
    func echo<Value: Equatable>(_ value: Value) -> Value
    func run<Value>(_ body: () throws -> Value) rethrows -> Value
}

@Mockable
private protocol AssociatedOnly<Element> {
    associatedtype Element: Sendable where Element: Equatable
}

@Mockable
private protocol StaticGenericService {
    static func identity<Value: Equatable>(_ value: Value) -> Value
}

@MainActor
@Mockable
private protocol MainActorService {
    static var enabled: Bool { get }
    func title() -> String
}

@Mockable
private protocol SelfService: AnyObject {
    static func make() -> Self
    func clone() -> Self
    func isSame(as other: Self) -> Bool
}

@Mockable
private protocol OwnershipService {
    func borrow(_ value: borrowing String) -> Int
    func consume(_ value: consuming String) -> Int
    func send(_ value: sending String) -> Int
}

@Mockable
private protocol ProtocolWhereService<Element> where Element: Equatable {
    associatedtype Element
    mutating func update() -> Int
}

@Test
private func generatedMockSupportsMethodsPropertiesAndTypedDSL() async throws {
    let mock = WeatherServiceMock()
    let cities = ArgumentCaptor<String>()
    var performedCities: [String] = []

    Given(mock, .temperature(for: .value("Toronto"), willReturn: 20, 21))
    Given(mock, .save(.any))
    Given(mock, .greeting(willReturn: "hello"))
    Given(mock, .unit(willReturn: "C"))
    Given(mock, .unit(set: .any))
    Perform(mock, .temperature(for: .any) { performedCities.append($0) })

    #expect(try await mock.temperature(for: "Toronto") == 20)
    #expect(try await mock.temperature(for: "Toronto") == 21)
    #expect(try await mock.temperature(for: "Toronto") == 21)
    mock.save(7)
    #expect(mock.greeting() == "hello")
    #expect(mock.unit == "C")
    mock.unit = "F"

    Verify(mock, 3, .temperature(for: .capturing(cities)))
    Verify(mock, 1, .save(.value(7)))
    Verify(mock, 1, .greeting())
    Verify(mock, 1, .unit())
    Verify(mock, 1, .unit(set: .value("F")))
    #expect(cities.values == ["Toronto", "Toronto", "Toronto"])
    #expect(performedCities == ["Toronto", "Toronto", "Toronto"])
}

@Test
private func generatedMockSupportsStaticMembersSubscriptsAndInitializers() {
    let mock = AdvancedServiceMock(seed: 1)

    Given(AdvancedServiceMock.self, .make(.value(2), willReturn: "two"))
    Given(AdvancedServiceMock.self, .sharedValue(willReturn: 10))
    Given(AdvancedServiceMock.self, .sharedValue(set: .any))
    Given(mock, .subscriptGet(.value("answer"), willReturn: 42))
    Given(mock, .subscriptSet(.value("answer"), value: .value(43)))

    #expect(AdvancedServiceMock.make(2) == "two")
    #expect(AdvancedServiceMock.sharedValue == 10)
    AdvancedServiceMock.sharedValue = 11
    #expect(mock["answer"] == 42)
    mock["answer"] = 43

    Verify(AdvancedServiceMock.self, 1, .make(.value(2)))
    Verify(AdvancedServiceMock.self, 1, .sharedValue())
    Verify(AdvancedServiceMock.self, 1, .sharedValue(set: .value(11)))
    Verify(mock, 1, .subscriptGet(.value("answer")))
    Verify(mock, 1, .subscriptSet(.value("answer"), value: .value(43)))
    Verify(mock, 1, .initializer(seed: .value(1)))
}

@Test
private func generatedMockSupportsAssociatedTypesOverloadsVariadicsAndInout() {
    let mock = RepositoryMock<String>()
    var value = 5

    Given(mock, .load(willReturn: "loaded"))
    Given(mock, .convert(.value(1), willReturn: "one"))
    Given(mock, .convert(.value("two"), willReturn: 2))
    Given(mock, .total(.value([1, 2, 3]), willReturn: 6))
    Given(mock, .mutate(.value(5)))

    #expect(mock.load() == "loaded")
    #expect(mock.convert(1) == "one")
    #expect(mock.convert("two") == 2)
    #expect(mock.total(1, 2, 3) == 6)
    mock.mutate(&value)

    Verify(mock, 1, .load())
    Verify(mock, 1, .convert(.value(1)))
    Verify(mock, 1, .convert(.value("two")))
    Verify(mock, 1, .total(.value([1, 2, 3])))
    Verify(mock, 1, .mutate(.value(5)))
}

@Test
private func generatedActorMockSupportsNonisolatedConfiguration() async {
    let mock = WorkerMock()
    Given(mock, .work(.any, willReturn: "done"))

    #expect(await mock.work(1) == "done")
    Verify(mock, 1, .work(.value(1)))
}

@Test
private func generatedMockSupportsTypedThrows() throws {
    let returning = TypedThrowerMock()
    Given(returning, .load(.value("count"), willReturn: 3))
    #expect(try returning.load("count") == 3)

    let throwing = TypedThrowerMock()
    Given(throwing, .load(.any, willThrow: .unavailable))
    let error = #expect(throws: LoadFailure.self) { try throwing.load("missing") }
    #expect(error == .unavailable)

    Verify(returning, 1, .load(.value("count")))
    Verify(throwing, 1, .load(.value("missing")))
}

@Test
private func generatedMockIsolatesGenericSpecializationsAndSupportsRethrows() throws {
    let mock = GenericServiceMock()

    Given(mock, .echo(.value("input"), willReturn: "output"))
    Given(mock, .echo(.value(1), willReturn: 2))
    Given(mock, .run(willReturn: 42))

    #expect(mock.echo("input") == "output")
    #expect(mock.echo(1) == 2)
    #expect(try mock.run { () throws -> Int in 0 } == 42)

    Verify(mock, 1, .echo(.value("input")))
    Verify(mock, 1, .echo(.value(1)))
    Verify(mock, 1, .run(returning: Int.self))
}

@Test
private func generatedMockSupportsUnusedConstrainedPrimaryAssociatedType() {
    let mock = AssociatedOnlyMock<String>()
    let value: any AssociatedOnly<String> = mock
    _ = value
}

@Test
private func generatedStaticGenericMethodsIsolateSpecializations() {
    Given(StaticGenericServiceMock.self, .identity(.value("input"), willReturn: "output"))
    Given(StaticGenericServiceMock.self, .identity(.value(1), willReturn: 2))

    #expect(StaticGenericServiceMock.identity("input") == "output")
    #expect(StaticGenericServiceMock.identity(1) == 2)
    Verify(StaticGenericServiceMock.self, 1, .identity(.value("input")))
    Verify(StaticGenericServiceMock.self, 1, .identity(.value(1)))
}

@Test @MainActor
private func generatedGlobalActorMockKeepsConfigurationUsable() {
    let mock = MainActorServiceMock()
    Given(mock, .title(willReturn: "ready"))
    Given(MainActorServiceMock.self, .enabled(willReturn: true))

    #expect(mock.title() == "ready")
    #expect(MainActorServiceMock.enabled)
    Verify(mock, 1, .title())
    Verify(MainActorServiceMock.self, 1, .enabled())
}

@Test
private func generatedMockSupportsStandaloneSelfRequirements() {
    let mock = SelfServiceMock()
    Given(mock, .clone(willReturn: mock))
    Given(mock, .isSame(as: .sameInstance(mock), willReturn: true))
    Given(SelfServiceMock.self, .make(willReturn: mock))

    #expect(mock.clone() === mock)
    #expect(mock.isSame(as: mock))
    #expect(SelfServiceMock.make() === mock)
    Verify(mock, 1, .clone())
    Verify(mock, 1, .isSame(as: .sameInstance(mock)))
    Verify(SelfServiceMock.self, 1, .make())
}

@Test
private func generatedMockSnapshotsCopyableOwnershipParameters() {
    let mock = OwnershipServiceMock()
    Given(mock, .borrow(.value("borrowed"), willReturn: 1))
    Given(mock, .consume(.value("consumed"), willReturn: 2))
    Given(mock, .send(.value("sent"), willReturn: 3))

    #expect(mock.borrow("borrowed") == 1)
    #expect(mock.consume("consumed") == 2)
    #expect(mock.send("sent") == 3)
    Verify(mock, 1, .borrow(.value("borrowed")))
    Verify(mock, 1, .consume(.value("consumed")))
    Verify(mock, 1, .send(.value("sent")))
}

@Test
private func generatedUntypedThrowingMemberReturnsFrameworkErrorWhenUnstubbed() async {
    let mock = WeatherServiceMock()
    await #expect(throws: MockError.self) {
        try await mock.temperature(for: "Toronto")
    }
}

@Test
private func generatedMockPreservesProtocolWhereAndDropsValueMutationModifier() {
    let mock = ProtocolWhereServiceMock<String>()
    Given(mock, .update(willReturn: 1))
    #expect(mock.update() == 1)
    Verify(mock, 1, .update())
}
