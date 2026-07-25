# Mock4Swift

`Mock4Swift` creates strict protocol mocks at compile time with Swift 6.3 macros. It takes inspiration from [SwiftyMocky](https://github.com/MakeAWishFoundation/SwiftyMocky), without Sourcery or checked-in generated source files.

## Installation

Add the package to a Swift 6.3 project, then add `Mock4Swift`, exactly one runner adapter, and the build plugin. Attach the plugin to every target that declares an inherited `@Mockable` protocol:

```swift
.testTarget(
    name: "AppTests",
    dependencies: [
        .product(name: "Mock4Swift", package: "mock-4-swift"),
        .product(name: "Mock4SwiftTesting", package: "mock-4-swift"),
        // or: .product(name: "Mock4SwiftXCTest", package: "mock-4-swift")
    ],
    plugins: [
        .plugin(name: "Mock4SwiftBuildPlugin", package: "mock-4-swift"),
    ]
)
```

The plugin resolves inherited protocols and composition aliases from the target and its reachable SwiftPM source dependencies. Direct protocols still use the macro alone.

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

Given(weather).temperature(for: .value("Toronto")).willReturn(20, 21)
Given(weather).unit.willReturn("C")
Given(weather).unit(set: .any)
Perform(weather).temperature(for: .any) { city in print(city) }

let value = try await weather.temperature(for: "Toronto")
weather.unit = "F"

Verify(weather, 1).temperature(for: .value("Toronto"))
Verify(weather, 1).unit(set: .value("F"))
```

Return sequences and throw sequences each consume values in order, then repeat the final outcome. Throwing members can mix typed outcomes in one registration:

```swift
Given(service).load(.any)
    .willReturn(cached)
    .thenThrow(.offline)
    .thenReturn(fresh)
```

Throwing `Void` members use `willSucceed`/`thenSucceed`; transient noncopyable members use `willProduce`/`thenProduce`. When registrations overlap, the matcher with the most non-`.any` parameters wins; the newest registration wins a tie.

## Matching, capture, and reset

`Parameter<Value>` provides `.any`, `.value(_:)` for equatable values, `.value(_:by:)`, `.matching(_:)`, `.sameInstance(_:)`, and `.capturing(_:)`:

```swift
let cities = ArgumentCaptor<String>()
Verify(weather, .atLeast(1)).temperature(for: .capturing(cities))
let lastCity = cities.lastValue

resetMock(weather)                         // all state
resetMock(weather, scopes: [.invocations]) // selected state
resetMock(ServiceMock.self, scopes: [.stubs, .actions])
```

Verification counts include integer literals, `.never`, `.exactly`, `.atLeast`, `.atMost`, and `.between`.

Strict in-order verification can span instance and static mocks:

```swift
VerifyInOrder { order in
    order.expect(repository).load(.value(id))
    order.expect(cache).save(.value(item))
    order.expect(NotifierMock.self).notify()
}
```

The first expectation may match anywhere in participating mocks' history. Each later expectation must match the immediate next participating invocation; calls before the first, after the last, and on mocks without expectations are ignored.

## Static members and subscripts

```swift
Given(ServiceMock.self).make(.value(2)).willReturn("two")
Given(mock).subscriptGet(.value("answer")).willReturn(42)
Given(mock).subscriptSet(.value("answer"), value: .value(43))

Verify(ServiceMock.self, 1).make(.value(2))
Verify(mock, 1).subscriptGet(.value("answer"))
```

Static state is isolated by concrete mock metatype and generic specialization. Required initializers construct without stubbing, record their arguments, and can be checked with `Verify(mock).initializer(...)`. Generic initializers and value-pack initializers use the same typed verification selector.

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
Given(mock).inspect(.matching { $0.raw == 7 }).willProduce({ 1 })
Verify(mock, 1).inspect()
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
Perform(mock).load(.value(4)) { key, completion in completion(key + 1) }
mock.load(4) { value in print(value) }
```

This applies to `rethrows` too. Multiple ordinary nonescaping closure parameters are supported. Nonescaping initializer closures remain unsupported because an initializer cannot safely retain or replay them.

## Inherited protocols and composition aliases

Attach `@Mockable` to the child protocol. The build plugin recursively collects requirements from parent protocols in the same package or a reachable SwiftPM source dependency:

```swift
protocol Parent {
    func inherited(_ value: Int) -> String
}

@Mockable
protocol Child: Parent {
    init(seed: Int)
    func own() -> Int
}
```

`ChildMock` includes parent and child methods, properties, subscripts, initializers, typed DSL builders, channels, and resets. Composition aliases work through an annotated protocol:

```swift
typealias Combined = ParentA & ParentB

@Mockable
protocol CombinedService: Combined {}
```

External parents need no extra macro arguments:

```swift
import ExternalServices

@Mockable
protocol LocalService: ExternalServices.Service {}
```

Inherited mocks must be top-level `internal`, `package`, or `public` protocols, and their requirement types must be visible from generated source. Parent protocols from another package must be `public`. Direct, non-inherited mocks retain `private` and `fileprivate` support.

## Objective-C protocols

On Apple platforms, `@Mockable` supports `@objc` protocols inheriting `NSObjectProtocol`, including optional methods and properties. Generated mocks subclass `NSObject`, preserve Objective-C attributes/selectors, and provide the normal strict typed DSL. This support is unavailable on Linux.

## Strict behavior

Generated mocks do not invent defaults for `Void`, optionals, properties, setters, or subscripts. Value-returning members need a matching `Given`; `Perform` also satisfies `Void` members because it installs the required `Void` outcome. Untyped throwing members throw `MockError.unstubbed`. Nonthrowing, `rethrows`, and incompatible typed-throws members stop with a precise precondition failure because they cannot legally throw a framework error. Required initializers are the only unstubbed exception.

## Test runners

`Mock4SwiftTesting.Verify` records a failed `VerificationResult` with `Testing.Issue.record` and the caller's `SourceLocation`. `Mock4SwiftXCTest.Verify` uses `XCTFail(_:file:line:)`. If both adapters are imported, qualify `Verify` with the module name.

## Swift 6.3 limits

Distributed actors are unsupported. Protocol requirements cannot use opaque `some` results in Swift; `some` input parameters are supported. Swift 6.3 rejects noncopyable associated types, so Mock4Swift diagnoses them precisely. Parameter packs currently require one pack parameter, and named noncopyable types require `@MockNoncopyable`.

Inherited protocol resolution requires ordinary, unconditional top-level Swift source reachable through the target's SwiftPM dependency graph. Binary XCFrameworks, SDK and precompiled modules, conditional declarations, macro-synthesized declarations, and dependency plugin-generated source are unsupported. Generic requirements with several noncopyable arguments require a named wrapper parameter. Transient requirements with nonescaping callbacks, nonescaping initializer closures, and settable parameter-pack subscripts remain excluded with targeted diagnostics.
