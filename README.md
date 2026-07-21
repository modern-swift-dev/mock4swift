# Mock4Swift

`Mock4Swift` creates strict protocol mocks at compile time with Swift 6.3 macros. It takes inspiration from [SwiftyMocky](https://github.com/MakeAWishFoundation/SwiftyMocky), without Sourcery, source scanning, a CLI, a build plugin, or generated source files.

## Installation

Add the package to a Swift 6.3 project, then add `Mock4Swift` and exactly one runner adapter to the test target:

```swift
.product(name: "Mock4Swift", package: "mock-4-swift"),
.product(name: "Mock4SwiftTesting", package: "mock-4-swift"),
// or: .product(name: "Mock4SwiftXCTest", package: "mock-4-swift")
```

The package supports Swift 6.3 on Linux and iOS 17, macOS 13, tvOS 17, and watchOS 10 or newer.

For progressive, runnable examples covering basic through advanced mocking, see the
[samples guide](samples/README.md).

## Basic usage

```swift
import Mock4Swift
import Mock4SwiftTesting

@Mockable
protocol WeatherService {
    var unit: String { get set }
    func temperature(for city: String) async throws -> Double
}

let weather = WeatherServiceMock()

Given(weather, .temperature(for: .value("Toronto"), willReturn: 20, 21))
Given(weather, .unit(willReturn: "C"))
Given(weather, .unit(set: .any))
Perform(weather, .temperature(for: .any) { city in print(city) })

let value = try await weather.temperature(for: "Toronto")
weather.unit = "F"

Verify(weather, 1, .temperature(for: .value("Toronto")))
Verify(weather, 1, .unit(set: .value("F")))
```

Return sequences and throw sequences each consume values in order, then repeat the final outcome. When registrations overlap, the matcher with the most non-`.any` parameters wins; the newest registration wins a tie.

## Matching, capture, and reset

`Parameter<Value>` provides `.any`, `.value(_:)` for equatable values, `.value(_:by:)`, `.matching(_:)`, `.sameInstance(_:)`, and `.capturing(_:)`:

```swift
let cities = ArgumentCaptor<String>()
Verify(weather, .atLeast(1), .temperature(for: .capturing(cities)))
let lastCity = cities.lastValue

resetMock(weather)                         // all state
resetMock(weather, scopes: [.invocations]) // selected state
resetMock(ServiceMock.self, scopes: [.stubs, .actions])
```

Verification counts include integer literals, `.never`, `.exactly`, `.atLeast`, `.atMost`, and `.between`.

## Static members and subscripts

```swift
Given(ServiceMock.self, .make(.value(2), willReturn: "two"))
Given(mock, .subscriptGet(.value("answer"), willReturn: 42))
Given(mock, .subscriptSet(.value("answer"), value: .value(43)))

Verify(ServiceMock.self, 1, .make(.value(2)))
Verify(mock, 1, .subscriptGet(.value("answer")))
```

Static state is isolated by concrete mock metatype and generic specialization. Required initializers construct without stubbing, record their arguments, and can be checked with `Verify(mock, .initializer(...))`. Generic initializers and value-pack initializers use the same typed factory.

## Noncopyable requirements

Use `@MockNoncopyable` when a requirement mentions a named noncopyable type. Requirements that syntactically use `~Copyable` are selected automatically:

```swift
struct Token: ~Copyable { let raw: Int }

@Mockable
protocol TokenService: ~Copyable {
    @MockNoncopyable
    func inspect(_ token: borrowing Token) -> Int
}

let mock = TokenServiceMock()
Given(mock, .inspect(.matching { $0.raw == 7 }, willProduce: { 1 }))
Verify(mock, 1, .inspect())
```

These members use a transient channel: arguments are borrowed and never retained, `.any` and `.matching` select a producer, and `willProduce` sequences repeat their final producer. `Perform` receives borrowed arguments. Post-call verification is count-only, so `.inspect()` takes no argument matchers. `Parameter<Value>` supports noncopyable values; `.value` and captors remain copyable-only.

## Supported protocol syntax

`@Mockable` supports:

- instance and static methods, properties, and subscripts;
- read-only/read-write properties and subscripts, including async, untyped/typed-throwing getters and static or generic subscripts;
- sync/async methods, untyped throws, typed throws, and `rethrows`;
- generic methods, initializers, and subscripts with constraints;
- standard value packs, plus `some Protocol` input parameters;
- associated and primary associated types with constraints;
- overloads, variadics, `inout` snapshots, and copyable ownership modifiers;
- `Self` inputs/results and dependent `Self.Associated` paths;
- `AnyObject`, `Sendable`, `Actor`, `~Copyable`, protocol/member availability, and global-actor isolation.

Nonescaping callback values are forwarded synchronously to `Perform` and are never retained; remaining arguments stay matchable and verifiable:

```swift
Perform(mock, .load(.value(4)) { key, completion in completion(key + 1) })
mock.load(4) { value in print(value) }
```

This applies to `rethrows` too. Multiple ordinary nonescaping closure parameters are supported. Nonescaping initializer closures remain unsupported because an initializer cannot safely retain or replay them.

## Inherited protocols and composition aliases

Peer macros cannot inspect requirements inherited from a custom protocol. Declare the complete witness surface on a handwritten final mock and use `@MockableMembers`:

```swift
protocol Parent {
    func inherited(_ value: Int) -> String
}

protocol Child: Parent {
    func own() -> Int
}

@MockableMembers
final class ChildMock: Child {
    init(seed: Int)
    func inherited(_ value: Int) -> String
    func own() -> Int
}
```

The macro supplies bodies, typed DSL factories, channels, resets, and `Mock` conformance. Bodyless methods, get/set properties, and initializers are supported. Swift rejects bodyless class subscripts before accessor-macro synthesis; use the accessor-body escape hatch below.

This escape hatch also supports protocol-composition aliases because the handwritten mock declares the complete witness surface:

```swift
typealias Combined = ParentA & ParentB

@MockableMembers
final class CombinedMock: Combined {
    func parentAMember() -> Int
    func parentBMember() -> String
}
```

For inherited subscripts, invoke `#MockableAccessor()` in each accessor body. The setter needs an explicit `Void` context:

```swift
@MockableMembers
final class IndexedMock: IndexedParent {
    subscript(_ key: String) -> Int {
        get { #MockableAccessor() }
        set { #MockableAccessor() as Void }
    }
}
```

This generates the usual `subscriptGet` and `subscriptSet` DSL. Swift 6.3 rejects the originally proposed `@MockableAccessor get` / `set` form before macro synthesis; the freestanding expression macro is the replacement.

## Objective-C protocols

On Apple platforms, `@Mockable` supports `@objc` protocols inheriting `NSObjectProtocol`, including optional methods and properties. Generated mocks subclass `NSObject`, preserve Objective-C attributes/selectors, and provide the normal strict typed DSL. This support is unavailable on Linux.

## Strict behavior

Generated mocks do not invent defaults for `Void`, optionals, properties, setters, or subscripts. Value-returning members need a matching `Given`; `Perform` also satisfies `Void` members because it installs the required `Void` outcome. Untyped throwing members throw `MockError.unstubbed`. Nonthrowing, `rethrows`, and incompatible typed-throws members stop with a precise precondition failure because they cannot legally throw a framework error. Required initializers are the only unstubbed exception.

## Test runners

`Mock4SwiftTesting.Verify` records a failed `VerificationResult` with `Testing.Issue.record` and the caller's `SourceLocation`. `Mock4SwiftXCTest.Verify` uses `XCTFail(_:file:line:)`. If both adapters are imported, qualify `Verify` with the module name.

## Swift 6.3 limits

Distributed actors are unsupported. Protocol requirements cannot use opaque `some` results in Swift; `some` input parameters are supported. Swift 6.3 rejects noncopyable associated types, so Mock4Swift diagnoses them precisely. Parameter packs currently require one pack parameter, and named noncopyable types require `@MockNoncopyable`.

Direct `@Mockable` generation cannot inspect custom inherited protocols or protocol-composition aliases; use `@MockableMembers`. Generic requirements with several noncopyable arguments require a named wrapper parameter. Transient requirements with nonescaping callbacks, nonescaping initializer closures, and settable parameter-pack subscripts remain excluded with targeted diagnostics.
