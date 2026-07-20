import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import Mock4SwiftMacros

final class MockableMacroTests: XCTestCase {
    private let macros: [String: Macro.Type] = [
        "Mockable": MockableMacro.self,
        "MockableMembers": MockableMembersMacro.self,
        "_Mock4SwiftBody": MockableBodyMacro.self,
        "_Mock4SwiftAccessor": MockableAccessorMacro.self,
    ]

    func testRejectsNonProtocol() {
        assertMacroExpansion(
            """
            @Mockable
            struct Service {}
            """,
            expandedSource: """
            struct Service {}
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Mockable can only be attached to a protocol", line: 1, column: 1),
            ],
            macros: macros
        )
    }

    func testEmptyProtocol() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Empty {}
            """,
            expandedSource: """
            protocol Empty {}

            final class EmptyMock: Empty, Mock {
                struct Given {
                    fileprivate let apply: (EmptyMock) -> Void
                }

                struct Verify {
                    fileprivate let apply: (EmptyMock, Count) -> VerificationResult
                }

                struct Perform {
                    fileprivate let apply: (EmptyMock) -> Void
                }

                func given(_ given: Given) {
                    given.apply(self)
                }
                func perform(_ perform: Perform) {
                    perform.apply(self)
                }
                func verification(_ verify: Verify, count: Count) -> VerificationResult {
                    verify.apply(self, count)
                }
                func resetMock(_ scopes: MockScope...) {
                }
            }
            """,
            macros: macros
        )
    }

    func testRejectsCustomProtocolInheritance() {
        assertMacroExpansion(
            """
            protocol Parent {}
            @Mockable
            protocol Child: Parent {}
            """,
            expandedSource: """
            protocol Parent {}
            protocol Child: Parent {}
            """,
            diagnostics: [
                DiagnosticSpec(message: "@Mockable cannot inspect inherited protocol 'Parent'; use @MockableMembers on a handwritten mock", line: 2, column: 1),
            ],
            macros: macros
        )
    }

    func testGenericMethodUsesRegistry() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Service {
                func echo<Value>(_ value: Value) -> Value
            }
            """,
            expandedSource: """
            protocol Service {
                func echo<Value>(_ value: Value) -> Value
            }

            final class ServiceMock: Service, Mock {
                private let _genericMockRegistry = GenericMockRegistry()

                struct Given {
                    fileprivate let apply: (ServiceMock) -> Void

                    static func echo<Value>(_ matching0: Parameter<Value>, willReturn values: Value...) -> Self {
                        Self { mock in
                        let member: MockMember<Value, Value> = mock._genericMockRegistry.member(key: "_mock_echo_0", types: [Value.self]) {
                            MockMember(name: "echo_:")
                        }
                        member.addStub(matching: { arguments in
                                matching0.matches(arguments)
                            }, specificity: matching0.specificity, outcomes: values.map(StubOutcome.returnValue))
                    }
                    }
                }

                struct Verify {
                    fileprivate let apply: (ServiceMock, Count) -> VerificationResult

                    static func echo<Value>(_ matching0: Parameter<Value>) -> Self {
                        Self { mock, count in
                        let member: MockMember<Value, Value> = mock._genericMockRegistry.member(key: "_mock_echo_0", types: [Value.self]) {
                            MockMember(name: "echo_:")
                        }
                        return member.verification(matching: { arguments in
                                matching0.matches(arguments)
                            }, count: count)
                    }
                    }
                }

                struct Perform {
                    fileprivate let apply: (ServiceMock) -> Void

                    static func echo<Value>(_ matching0: Parameter<Value>, _ action: @escaping (Value) -> Void) -> Self {
                        Self { mock in
                        let member: MockMember<Value, Value> = mock._genericMockRegistry.member(key: "_mock_echo_0", types: [Value.self]) {
                            MockMember(name: "echo_:")
                        }
                        member.addAction(matching: { arguments in
                                matching0.matches(arguments)
                            }, specificity: matching0.specificity) { arguments in
                            action(arguments)
                        }
                    }
                    }
                }

                func given(_ given: Given) {
                    given.apply(self)
                }
                func perform(_ perform: Perform) {
                    perform.apply(self)
                }
                func verification(_ verify: Verify, count: Count) -> VerificationResult {
                    verify.apply(self, count)
                }
                func resetMock(_ scopes: MockScope...) {
                    _genericMockRegistry.reset(scopes)
                }

                    func echo<Value>(_ value: Value) -> Value {
                        let member: MockMember<Value, Value> = _genericMockRegistry.member(key: "_mock_echo_0", types: [Value.self]) {
                            MockMember(name: "echo_:")
                        }
                        do {
                            return try member.invoke(value)
                        }
                        catch {
                            preconditionFailure("Unstubbed nonthrowing member echo_:: \\(error)")
                        }
                    }
            }
            """,
            macros: macros
        )
    }

    func testRethrowsOmitsNonescapingClosureFromRecordedArguments() throws {
        let declaration: DeclSyntax = """
            protocol Service {
                func run<Value>(_ body: () throws -> Value) rethrows -> Value
            }
            """
        let protocolDecl = try XCTUnwrap(declaration.as(ProtocolDeclSyntax.self))
        let attribute: AttributeSyntax = "@Mockable"
        let context = BasicMacroExpansionContext(lexicalContext: [])

        let source = try XCTUnwrap(
            MockableMacro.expansion(of: attribute, providingPeersOf: protocolDecl, in: context).first
        ).description

        XCTAssertTrue(source.contains("MockMember<Void, Value>"))
        XCTAssertTrue(source.contains("func run<Value>(_ body: () throws -> Value) rethrows -> Value"))
        XCTAssertTrue(source.contains("static func run<Value>(returning _: Value.Type) -> Self"))
        XCTAssertTrue(source.contains("static func run<Value>(returning _: Value.Type, _ action: @escaping () -> Void) -> Self"))
        XCTAssertTrue(source.contains("Invalid or unstubbed rethrows member"))
        XCTAssertFalse(source.contains("willThrow"))
        XCTAssertFalse(source.contains("Parameter<() throws -> Value>"))
    }

    func testAssociatedTypesUseDistinctGenericParametersAndTypealiases() throws {
        let source = try peerSource(
            """
            protocol Repository<Element> {
                associatedtype Element: Equatable
                associatedtype Key where Key: Hashable
                func load() -> Element
            }
            """
        )

        XCTAssertTrue(source.contains("RepositoryMock<ElementType: Equatable, KeyType>"))
        XCTAssertTrue(source.contains("where KeyType: Hashable"))
        XCTAssertTrue(source.contains("typealias Element = ElementType"))
        XCTAssertTrue(source.contains("typealias Key = KeyType"))
        XCTAssertTrue(source.contains("MockMember<Void, ElementType>"))
    }

    func testStaticGenericMethodUsesTypedStaticRegistry() throws {
        let source = try peerSource(
            """
            protocol Factory {
                static func make<Value: Equatable>(_ value: Value) -> Value where Value: Sendable
            }
            """
        )

        XCTAssertTrue(source.contains("StaticMock"))
        XCTAssertTrue(source.contains("StaticMockRegistry.shared.member(owner: mock, key: \"_mock_make_0\", types: [Value.self])"))
        XCTAssertTrue(source.contains("static func make<Value: Equatable>"))
        XCTAssertTrue(source.contains("where Value: Sendable"))
        XCTAssertFalse(source.contains("_genericMockRegistry"))
    }

    func testGlobalActorAndAvailabilityArePreservedWithNonisolatedConfiguration() throws {
        let source = try peerSource(
            """
            @MainActor
            @available(macOS 14, *)
            protocol Service {
                func value() -> Int
            }
            """
        )

        XCTAssertTrue(source.hasPrefix("@MainActor\n@available(macOS 14, *)\nfinal class ServiceMock"))
        XCTAssertTrue(source.contains("nonisolated private let _mock_value_0"))
        XCTAssertTrue(source.contains("nonisolated static func value"))
        XCTAssertTrue(source.contains("nonisolated func given"))
    }

    func testStandaloneSelfRewritesToConcreteMock() throws {
        let source = try peerSource(
            """
            protocol Copying {
                func copy(_ other: Self) -> Self
                static func make() -> Self
            }
            """
        )

        XCTAssertTrue(source.contains("MockMember<CopyingMock, CopyingMock>"))
        XCTAssertTrue(source.contains("func copy(_ other: CopyingMock) -> CopyingMock"))
        XCTAssertTrue(source.contains("static func make() -> CopyingMock"))
    }

    func testRejectsDependentSelfMemberType() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Service {
                func load() -> Self.Value
            }
            """,
            expandedSource: """
            protocol Service {
                func load() -> Self.Value
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "dependent Self member types are not supported yet", line: 3, column: 5),
            ],
            macros: macros
        )
    }

    func testInitializersRecordSnapshotsAndExposeVerifyFactories() throws {
        let source = try peerSource(
            """
            protocol Service {
                init(seed: Int, labels: String...)
                init?(name: String)
                init() async throws(ServiceError)
            }
            """
        )

        XCTAssertTrue(source.contains("MockMember<(seed: Int, labels: [String]), Void>(name: \"initseed:labels:\")"))
        XCTAssertTrue(source.contains("required init(seed: Int, labels: String...)"))
        XCTAssertTrue(source.contains("_mock_initializer_0.record((seed: seed, labels: labels))"))
        XCTAssertTrue(source.contains("required init?(name: String)"))
        XCTAssertTrue(source.contains("_mock_initializer_1.record(name)"))
        XCTAssertTrue(source.contains("required init() async throws(ServiceError)"))
        XCTAssertTrue(source.contains("_mock_initializer_2.record(())"))
        XCTAssertTrue(source.contains("static func initializer(seed matching0: Parameter<Int>, labels matching1: Parameter<[String]>) -> Self"))
        XCTAssertTrue(source.contains("static func initializer(name matching0: Parameter<String>) -> Self"))
        XCTAssertTrue(source.contains("static func initializer() -> Self"))
    }

    func testRejectsGenericInitializer() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Service {
                init<Value>(_ value: Value)
            }
            """,
            expandedSource: """
            protocol Service {
                init<Value>(_ value: Value)
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "generic initializer requirements are not supported yet", line: 3, column: 5),
            ],
            macros: macros
        )
    }

    func testRejectsNonescapingFunctionParameterOutsideRethrows() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Service {
                func load(_ completion: (Int) -> Void)
            }
            """,
            expandedSource: """
            protocol Service {
                func load(_ completion: (Int) -> Void)
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "nonescaping function parameters cannot be recorded; mark the parameter @escaping", line: 3, column: 5),
            ],
            macros: macros
        )
    }

    func testDiagnosesUnsupportedAccessorEffects() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Service {
                var value: Int { get async throws }
                subscript(_ key: String) -> Int { get async }
            }
            """,
            expandedSource: """
            protocol Service {
                var value: Int { get async throws }
                subscript(_ key: String) -> Int { get async }
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "async and throwing property accessors are not supported yet", line: 3, column: 5),
                DiagnosticSpec(message: "async and throwing subscript accessors are not supported yet", line: 4, column: 5),
            ],
            macros: macros
        )
    }

    func testDiagnosesNoncopyableAssociatedTypeAndMemberAvailability() {
        assertMacroExpansion(
            """
            @Mockable
            protocol Service {
                associatedtype Value: ~Copyable
                @available(macOS 99, *)
                func load() -> Int
            }
            """,
            expandedSource: """
            protocol Service {
                associatedtype Value: ~Copyable
                @available(macOS 99, *)
                func load() -> Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "noncopyable associated types are not supported yet", line: 3, column: 5),
                DiagnosticSpec(message: "member-level availability is not supported yet; apply @available to the protocol", line: 4, column: 5),
            ],
            macros: macros
        )
    }

    private func peerSource(_ source: DeclSyntax, file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let declaration = try XCTUnwrap(source.as(ProtocolDeclSyntax.self), file: file, line: line)
        let attribute: AttributeSyntax = "@Mockable"
        let context = BasicMacroExpansionContext(lexicalContext: [])
        return try XCTUnwrap(
            MockableMacro.expansion(of: attribute, providingPeersOf: declaration, in: context).first,
            file: file,
            line: line
        ).description
    }

    func testMockableMembersGeneratesPublicRuntimeSupportAndHelpers() throws {
        let source: DeclSyntax = """
            public final class ServiceMock: Service {
                public func value(_ input: Int) -> String
                public var flag: Bool
            }
            """
        let declaration = try XCTUnwrap(source.as(ClassDeclSyntax.self))
        let attribute: AttributeSyntax = "@MockableMembers"
        let context = BasicMacroExpansionContext(lexicalContext: [])
        let generated = try MockableMembersMacro.expansion(
            of: attribute,
            providingMembersOf: declaration,
            conformingTo: [],
            in: context
        ).map(\.description).joined(separator: "\n")

        XCTAssertTrue(generated.contains("private let _mock_value_0"))
        XCTAssertTrue(generated.contains("private let _mock_flag_get_1"))
        XCTAssertTrue(generated.contains("public struct Given"))
        XCTAssertTrue(generated.contains("public struct Verify"))
        XCTAssertTrue(generated.contains("public struct Perform"))

        let method = try XCTUnwrap(declaration.memberBlock.members.first?.decl)
        let helper = try MockableMembersMacro.expansion(
            of: attribute,
            attachedTo: declaration,
            providingAttributesFor: method,
            in: context
        )
        XCTAssertEqual(helper.first?.trimmedDescription, "@_Mock4SwiftBody(0)")
    }

    func testMockableMembersDiagnosesBodylessSubscriptCompilerLimitation() throws {
        let source: DeclSyntax = """
            final class ServiceMock: Service {
                subscript(_ key: String) -> Int
            }
            """
        let declaration = try XCTUnwrap(source.as(ClassDeclSyntax.self))
        let context = BasicMacroExpansionContext(lexicalContext: [])
        let attribute: AttributeSyntax = "@MockableMembers"

        _ = try MockableMembersMacro.expansion(
            of: attribute,
            providingMembersOf: declaration,
            conformingTo: [],
            in: context
        )

        XCTAssertEqual(context.diagnostics.first?.message, "bodyless class subscripts are rejected by Swift before accessor macro synthesis; provide the subscript implementation manually")
    }
}
