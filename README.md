# Mock4Swift

`Mock4Swift` creates strict protocol mocks at compile time with Swift 6.3 macros. It takes inspiration from [SwiftyMocky](https://github.com/MakeAWishFoundation/SwiftyMocky), without Sourcery, source scanning, a CLI, a build plugin, or generated source files.

## Installation

Add the package to a Swift 6.3 project, then add `Mock4Swift` and exactly one runner adapter to the test target:

```swift
.product(name: "Mock4Swift", package: "mock-4-swift"),
.product(name: "Mock4SwiftTesting", package: "mock-4-swift"),
// or: .product(name: "Mock4SwiftXCTest", package: "mock-4-swift")
```

The package supports iOS 17, macOS 13, tvOS 17, and watchOS 10 or newer.

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

Static state is isolated by concrete mock metatype and generic specialization. Required initializers construct without stubbing, record their arguments, and can be checked with `Verify(mock, .initializer(...))`.

## Supported protocol syntax

`@Mockable` supports:

- instance and static methods and properties;
- read-only and read-write synchronous subscripts;
- sync/async methods, untyped throws, typed throws, and `rethrows`;
- generic methods and static generic methods with constraints;
- associated and primary associated types with constraints;
- overloads, variadics, `inout` snapshots, and copyable ownership modifiers;
- standalone `Self` inputs and results;
- `AnyObject`, `Sendable`, `Actor`, protocol-level availability, and global-actor isolation.

For `rethrows`, nonescaping throwing closures cannot legally be retained as invocation data. Mock4Swift omits those closure values from matching while retaining other parameters. A generic result type may therefore be supplied to verification explicitly, for example `.run(returning: Int.self)`.

## Inherited protocols

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

The macro supplies bodies, typed DSL factories, channels, resets, and `Mock` conformance. Bodyless methods, get/set properties, and initializers are supported. Swift rejects bodyless class subscripts before accessor-macro synthesis, so inherited subscript witnesses must currently be implemented manually.

## Strict behavior

Generated mocks do not invent defaults for `Void`, optionals, properties, setters, or subscripts. Value-returning members need a matching `Given`; `Perform` also satisfies `Void` members because it installs the required `Void` outcome. Untyped throwing members throw `MockError.unstubbed`. Nonthrowing, `rethrows`, and incompatible typed-throws members stop with a precise precondition failure because they cannot legally throw a framework error. Required initializers are the only unstubbed exception.

## Test runners

`Mock4SwiftTesting.Verify` records a failed `VerificationResult` with `Testing.Issue.record` and the caller's `SourceLocation`. `Mock4SwiftXCTest.Verify` uses `XCTFail(_:file:line:)`. If both adapters are imported, qualify `Verify` with the module name.

## Version 1 limits

Opaque `some` requirements, parameter packs, dependent `Self.Associated` types, explicitly noncopyable recording, member-level availability, generic initializers, async/throwing property accessors, static/generic/async/throwing subscripts, and nonescaping non-`rethrows` function parameters are diagnosed rather than partially generated. Objective-C optional requirements, distributed actors, protocol-composition typealiases, and fully noncopyable argument recording are outside version 1.
