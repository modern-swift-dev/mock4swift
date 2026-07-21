# Mock4Swift samples

These samples are executable documentation. They compile and run with the package test suite, so the examples stay aligned with the public API.

## Run the samples

From the repository root:

```sh
swift test
```

The package requires Swift 6.3. Applications normally add `Mock4Swift` and exactly one verification adapter to their test target:

```swift
.product(name: "Mock4Swift", package: "mock-4-swift"),
.product(name: "Mock4SwiftTesting", package: "mock-4-swift"),
// Or use Mock4SwiftXCTest instead of Mock4SwiftTesting.
```

## Core workflow

Every sample follows the same three steps:

1. `Given` registers values or errors returned by generated mock members.
2. Test code calls the mock through the original protocol API.
3. `Verify` checks which generated members were invoked and how often.

`Perform` adds side effects, such as invoking a callback or recording a value. `resetMock` selectively clears invocations, stubs, or actions.

Mocks are strict. Mock4Swift does not invent defaults for `Void`, optionals, properties, setters, or subscripts. Untyped throwing requirements report `MockError.unstubbed`; unstubbed nonthrowing and incompatible typed-throwing requirements stop with a precondition failure because their signatures cannot return a framework error.

## Learning order

1. [`01_BasicMockingTests.swift`](Tests/01_BasicMockingTests.swift) — generate a mock, stub methods and properties, then verify calls.
2. [`02_StubsActionsAndStrictnessTests.swift`](Tests/02_StubsActionsAndStrictnessTests.swift) — sequences, errors, actions, strict behavior, and stub priority.
3. [`03_MatchingCaptureVerificationResetTests.swift`](Tests/03_MatchingCaptureVerificationResetTests.swift) — every matcher, argument capture, call counts, and reset scopes.
4. [`04_MembersAndInitializersTests.swift`](Tests/04_MembersAndInitializersTests.swift) — static members, subscripts, initializers, overloads, variadics, and `inout`.
5. [`05_AsyncActorsAndCallbacksTests.swift`](Tests/05_AsyncActorsAndCallbacksTests.swift) — async and typed-throwing members, actors, global actors, and callbacks.
6. [`06_GenericsAndLanguageFeaturesTests.swift`](Tests/06_GenericsAndLanguageFeaturesTests.swift) — generics, associated types, `Self`, ownership, packs, opaque inputs, and Objective-C protocols.
7. [`07_InheritedAndManualMocksTests.swift`](Tests/07_InheritedAndManualMocksTests.swift) — handwritten mocks for inheritance and protocol compositions.
8. [`08_NoncopyableTests.swift`](Tests/08_NoncopyableTests.swift) — transient producers and count-only verification for noncopyable values.
9. [`09_XCTestAdapterTests.swift`](Tests/09_XCTestAdapterTests.swift) — the same public DSL with XCTest.

## Deliberately non-runnable failures

Some failures cannot safely live in an always-green test target. For example, calling an unstubbed nonthrowing method intentionally traps:

```swift
// let mock = NonthrowingServiceMock()
// _ = mock.value() // Precondition failure: no legal error can be thrown here.
```

Macro diagnostics are compile-time failures and are documented rather than compiled. Current Swift 6.3 limits include distributed actors, opaque `some` results, noncopyable associated types, multiple noncopyable generic arguments without a wrapper, nonescaping initializer closures, and settable parameter-pack subscripts. Custom inherited protocols and protocol-composition aliases require the handwritten `@MockableMembers` approach shown in sample 7.
