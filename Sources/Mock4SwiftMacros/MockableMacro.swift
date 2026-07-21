import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct MockableMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            diagnose("@Mockable can only be attached to a protocol", at: declaration, in: context)
            return []
        }

        let inherited = protocolDecl.inheritanceClause?.inheritedTypes.map {
            $0.type.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
        } ?? []
        let markers = Set(["AnyObject", "Sendable", "Actor", "~Copyable", "NSObjectProtocol"])
        if let custom = inherited.first(where: { !markers.contains($0) }) {
            diagnose(
                "@Mockable cannot inspect inherited protocol '\(custom)'; use @MockableMembers on a handwritten mock",
                at: protocolDecl,
                in: context
            )
            return []
        }

        let generator = MockGenerator(protocolDecl: protocolDecl, isActor: inherited.contains("Actor"))
        guard generator.validate(in: context) else { return [] }
        return [DeclSyntax(stringLiteral: generator.render())]
    }
}

/// Syntax-only marker consumed by `@Mockable` and `@MockableMembers`.
public struct MockNoncopyableMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] { [] }
}

/// Fills inherited-subscript accessor bodies as `#MockableAccessor`.
public struct MockableExplicitAccessorMacro: ExpressionMacro {
    public static func expansion(
        of node: some FreestandingMacroExpansionSyntax,
        in context: some MacroExpansionContext
    ) throws -> ExprSyntax {
        let ancestorAccessor = firstAncestor(of: node, as: AccessorDeclSyntax.self)
        let ancestorSubscript = firstAncestor(of: node, as: SubscriptDeclSyntax.self)
        let lexicalSubscript = ancestorSubscript ?? context.lexicalContext.reversed().compactMap({ $0.as(SubscriptDeclSyntax.self) }).first
        let lexicalHeader = ancestorAccessor.map(accessorHeader) ?? context.lexicalContext.first?.trimmedDescription.trimmingCharacters(in: .whitespacesAndNewlines) ?? "get"
        let modeledSubscript: SubscriptDeclSyntax? = lexicalSubscript.flatMap { declaration in
            let accessors = lexicalHeader.contains("set") ? "get set" : lexicalHeader + " set"
            return DeclSyntax(stringLiteral: declaration.with(\.accessorBlock, nil).trimmedDescription + " { \(accessors) }").as(SubscriptDeclSyntax.self)
        }
        guard let info = enclosingMockInfo(context),
              let subscriptDecl = modeledSubscript,
              let member = SubscriptMember.make(
                  subscriptDecl,
                  index: 0,
                  access: "",
                  replacements: [:],
                  mockType: info.name,
                  factoryIsolation: info.isolated
              ).first(where: {
                  let kind = ancestorAccessor?.accessorSpecifier.text ?? (lexicalHeader.contains("set") ? "set" : "get")
                  return ($0.kind == .get) == (kind == "get")
              }) else {
            return ExprSyntax(stringLiteral: "preconditionFailure(\"#MockableAccessor must be used inside a mock subscript accessor\")")
        }
        let setup = member.witnessRegistryResolution
        let call = "try \(member.witnessChannelReference).invoke(\(member.invocationArguments))"
        if let typedError = member.typedError {
            return ExprSyntax(stringLiteral: "try { () throws(\(typedError)) -> \(member.outputType) in \(setup)do { return \(call) } catch let error as \(typedError) { throw error } catch { preconditionFailure(\"Invalid or unstubbed typed-throws member \(member.displayName): \\(error)\") } }()")
        }
        if member.isThrowing { return ExprSyntax(stringLiteral: "try { () throws -> \(member.outputType) in \(setup)return \(call) }()") }
        return ExprSyntax(stringLiteral: "{ \(setup)do { return \(call) } catch { preconditionFailure(\"Unstubbed nonthrowing member \(member.displayName): \\(error)\") } }()")
    }
}

private func firstAncestor<Node: SyntaxProtocol>(of node: some SyntaxProtocol, as type: Node.Type) -> Node? {
    var current = Syntax(node)?.parent
    while let syntax = current {
        if let result = syntax.as(Node.self) { return result }
        current = syntax.parent
    }
    return nil
}

/// Escape hatch driven by witness declarations authored in a handwritten mock.
public struct MockableMembersMacro: MemberMacro, MemberAttributeMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let generator = ManualMockGenerator(declaration: declaration, context: context) else { return [] }
        return generator.supportingMembers()
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        let modeledMembers = declaration.memberBlock.members.filter { isManualMockMember($0.decl) }
        guard isManualMockMember(DeclSyntax(member)),
              let index = modeledMembers.enumerated().first(where: { $0.element.decl.trimmedDescription == member.trimmedDescription })?.offset else { return [] }
        if let subscriptDecl = member.as(SubscriptDeclSyntax.self), hasExplicitMockableAccessors(subscriptDecl) || hasExpressionMockableAccessors(subscriptDecl) { return [] }
        let name = member.is(FunctionDeclSyntax.self) || member.is(InitializerDeclSyntax.self) ? "_Mock4SwiftBody" : "_Mock4SwiftAccessor"
        return [AttributeSyntax(stringLiteral: "@\(name)(\(index))")]
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let hasStatic = declaration.memberBlock.members.contains { member in
            if let function = member.decl.as(FunctionDeclSyntax.self) { return function.modifiers.contains { ["static", "class"].contains($0.name.text) } }
            if let variable = member.decl.as(VariableDeclSyntax.self) { return variable.modifiers.contains { ["static", "class"].contains($0.name.text) } }
            return false
        }
        return [try ExtensionDeclSyntax("extension \(type.trimmed): Mock\(raw: hasStatic ? ", StaticMock" : "") {}")]
    }
}

public struct MockableBodyMacro: BodyMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in context: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        guard let index = witnessIndex(node), let info = enclosingMockInfo(context) else { return [] }
        if let function = declaration.as(FunctionDeclSyntax.self) {
            let member = FunctionMember(declaration: function, index: index, access: "", replacements: [:], mockType: info.name, factoryIsolation: info.isolated)
            guard let generated = DeclSyntax(stringLiteral: member.witness).as(FunctionDeclSyntax.self), let body = generated.body else { return [] }
            return Array(body.statements)
        }
        if let initializer = declaration.as(InitializerDeclSyntax.self) {
            let member = InitializerMember(declaration: initializer, index: index, access: "", replacements: [:], mockType: info.name, factoryIsolation: info.isolated, isActor: info.isActor, isObjectiveC: false)
            guard let generated = DeclSyntax(stringLiteral: member.witness).as(InitializerDeclSyntax.self), let body = generated.body else { return [] }
            return Array(body.statements)
        }
        return []
    }
}

public struct MockableAccessorMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        guard let index = witnessIndex(node), let info = enclosingMockInfo(context) else { return [] }
        if let variable = declaration.as(VariableDeclSyntax.self) {
            let source: DeclSyntax = DeclSyntax(stringLiteral: variable.trimmedDescription + " { get set }")
            guard let synthesized = source.as(VariableDeclSyntax.self),
                  let member = PropertyMember.make(synthesized, index: index, access: "", replacements: [:], mockType: info.name, factoryIsolation: info.isolated).first,
                  let generated = DeclSyntax(stringLiteral: member.witness).as(VariableDeclSyntax.self),
                  let block = generated.bindings.first?.accessorBlock,
                  case .accessors(let accessors) = block.accessors else { return [] }
            return Array(accessors)
        }
        if let subscriptDecl = declaration.as(SubscriptDeclSyntax.self) {
            let source: DeclSyntax = DeclSyntax(stringLiteral: subscriptDecl.trimmedDescription + " { get }")
            guard let synthesized = source.as(SubscriptDeclSyntax.self),
                  let member = SubscriptMember.make(synthesized, index: index, access: "", replacements: [:], mockType: info.name, factoryIsolation: info.isolated).first,
                  let generated = DeclSyntax(stringLiteral: member.witness).as(SubscriptDeclSyntax.self),
                  let block = generated.accessorBlock,
                  case .accessors(let accessors) = block.accessors else { return [] }
            return Array(accessors)
        }
        return []
    }
}

private struct ManualMockGenerator {
    let generator: MockGenerator

    init?(declaration: some DeclGroupSyntax, context: some MacroExpansionContext) {
        let name: String
        let isActor: Bool
        if let classDecl = declaration.as(ClassDeclSyntax.self) {
            name = classDecl.name.text
            isActor = false
            guard classDecl.modifiers.contains(where: { $0.name.text == "final" }) else {
                diagnose("@MockableMembers requires a final class or actor", at: declaration, in: context)
                return nil
            }
        } else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
            name = actorDecl.name.text
            isActor = true
        } else {
            diagnose("@MockableMembers can only be attached to a final class or actor", at: declaration, in: context)
            return nil
        }
        guard name.hasSuffix("Mock") else {
            diagnose("@MockableMembers type name must end in 'Mock'", at: declaration, in: context)
            return nil
        }
        if let unsupported = declaration.memberBlock.members.compactMap({ $0.decl.as(SubscriptDeclSyntax.self) }).first(where: { $0.accessorBlock == nil }) {
            diagnose(
                "bodyless class subscripts are rejected by Swift before accessor macro synthesis; provide the subscript implementation manually",
                at: unsupported,
                in: context
            )
            return nil
        }
        let baseName = String(name.dropLast(4))
        let access = declaration.modifiers.compactMap { modifier -> String? in
            ["public", "package", "fileprivate", "private"].contains(modifier.name.text) ? modifier.name.text : nil
        }.first.map { $0 + " " } ?? ""
        let attributes = declaration.attributes.compactMap { element -> String? in
            guard let attribute = element.as(AttributeSyntax.self) else { return nil }
            let attributeName = attribute.attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
            return attributeName == "available" || (attributeName.hasSuffix("Actor") && attributeName != "MockableMembers") ? attribute.trimmedDescription : nil
        }.joined(separator: "\n")
        let members = declaration.memberBlock.members.compactMap { item -> String? in
            if let function = item.decl.as(FunctionDeclSyntax.self), function.body == nil { return stripWitnessModifiers(function.trimmedDescription) }
            if let variable = item.decl.as(VariableDeclSyntax.self), variable.bindings.first?.accessorBlock == nil {
                return stripWitnessModifiers(variable.trimmedDescription) + " { get set }"
            }
            if let subscriptDecl = item.decl.as(SubscriptDeclSyntax.self) {
                if subscriptDecl.accessorBlock == nil {
                    return stripWitnessModifiers(subscriptDecl.trimmedDescription) + " { get }"
                }
                if hasExplicitMockableAccessors(subscriptDecl) || hasExpressionMockableAccessors(subscriptDecl) {
                    let accessors: String = {
                        guard let block = subscriptDecl.accessorBlock, case .accessors(let list) = block.accessors else { return "get" }
                        return list.map { accessorHeader($0) }.joined(separator: " ")
                    }()
                    let signature = subscriptDecl.with(\.accessorBlock, nil).trimmedDescription
                    return stripWitnessModifiers(signature) + " { \(accessors.replacingOccurrences(of: "@MockableAccessor", with: "")) }"
                }
            }
            if let initializer = item.decl.as(InitializerDeclSyntax.self), initializer.body == nil {
                return stripWitnessModifiers(initializer.trimmedDescription)
            }
            return nil
        }.joined(separator: "\n")
        let attributePrefix = attributes.isEmpty ? "" : attributes + "\n"
        let inheritance = isActor ? ": Actor" : ""
        let source = "\(attributePrefix)\(access)protocol \(baseName)\(inheritance) {\n\(members)\n}"
        guard let protocolDecl = DeclSyntax(stringLiteral: source).as(ProtocolDeclSyntax.self) else {
            diagnose("@MockableMembers could not parse handwritten witnesses", at: declaration, in: context)
            return nil
        }
        let generator = MockGenerator(protocolDecl: protocolDecl, isActor: isActor)
        guard generator.validate(in: context) else { return nil }
        self.generator = generator
    }

    func supportingMembers() -> [DeclSyntax] { generator.supportingMembers() }
}

private func hasExplicitMockableAccessors(_ declaration: SubscriptDeclSyntax) -> Bool {
    guard let block = declaration.accessorBlock, case .accessors(let accessors) = block.accessors else { return false }
    return !accessors.isEmpty && accessors.allSatisfy { accessor in
        accessor.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            return attribute.attributeName.trimmedDescription.split(separator: ".").last == "MockableAccessor"
        }
    }
}

private func hasExpressionMockableAccessors(_ declaration: SubscriptDeclSyntax) -> Bool {
    guard let block = declaration.accessorBlock, case .accessors(let accessors) = block.accessors else { return false }
    return !accessors.isEmpty && accessors.allSatisfy { $0.body?.trimmedDescription.contains("#MockableAccessor") == true }
}

private func isManualMockMember(_ declaration: DeclSyntax) -> Bool {
    if let function = declaration.as(FunctionDeclSyntax.self) { return function.body == nil }
    if let variable = declaration.as(VariableDeclSyntax.self) { return variable.bindings.first?.accessorBlock == nil }
    if let subscriptDecl = declaration.as(SubscriptDeclSyntax.self) {
        return hasExplicitMockableAccessors(subscriptDecl) || hasExpressionMockableAccessors(subscriptDecl)
    }
    if let initializer = declaration.as(InitializerDeclSyntax.self) { return initializer.body == nil }
    return false
}

private func witnessIndex(_ node: AttributeSyntax) -> Int? {
    guard case .argumentList(let arguments) = node.arguments,
          let literal = arguments.first?.expression.as(IntegerLiteralExprSyntax.self) else { return nil }
    return Int(literal.literal.text)
}

private func stripWitnessModifiers(_ text: String) -> String {
    text.replacingOccurrences(
        of: #"\b(?:public|package|internal|fileprivate|private|required)\s+"#,
        with: "",
        options: .regularExpression
    )
}

private func enclosingMockInfo(_ context: some MacroExpansionContext) -> (name: String, isActor: Bool, isolated: String)? {
    for syntax in context.lexicalContext.reversed() {
        if let declaration = syntax.as(ClassDeclSyntax.self) {
            let isolated = declaration.attributes.contains { element in
                guard let attribute = element.as(AttributeSyntax.self) else { return false }
                let name = attribute.attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
                return name.hasSuffix("Actor") && name != "MockableMembers"
            }
            return (declaration.name.text, false, isolated ? "nonisolated " : "")
        }
        if let declaration = syntax.as(ActorDeclSyntax.self) {
            return (declaration.name.text, true, "nonisolated ")
        }
    }
    return nil
}

private struct MockGenerator {
    let protocolDecl: ProtocolDeclSyntax
    let isActor: Bool

    private var associatedTypes: [AssociatedTypeDeclSyntax] {
        protocolDecl.memberBlock.members.compactMap { $0.decl.as(AssociatedTypeDeclSyntax.self) }
    }
    private var replacements: [String: String] {
        Dictionary(uniqueKeysWithValues: associatedTypes.map { ($0.name.text, $0.name.text + "Type") })
    }
    private var mockType: String { protocolDecl.name.text + "Mock" }
    private var isObjectiveC: Bool {
        hasAttribute(named: "objc", in: protocolDecl.attributes)
            || protocolDecl.inheritanceClause?.inheritedTypes.contains(where: { $0.type.trimmedDescription.hasSuffix("NSObjectProtocol") }) == true
    }
    private var hasGlobalActor: Bool {
        protocolDecl.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            let name = attribute.attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
            return name.hasSuffix("Actor") && name != "Mockable"
        }
    }
    private var configurationIsolation: String { isActor || hasGlobalActor ? "nonisolated " : "" }

    private var access: String {
        for modifier in protocolDecl.modifiers {
            let value = modifier.name.text
            if value == "private" || value == "fileprivate" { return "fileprivate " }
            if value == "public" || value == "package" { return value + " " }
        }
        return ""
    }

    private var members: [GeneratedMember] {
        var result: [GeneratedMember] = []
        for (index, item) in protocolDecl.memberBlock.members.enumerated() {
            if let function = item.decl.as(FunctionDeclSyntax.self) {
                result.append(.function(FunctionMember(declaration: function, index: index, access: access, replacements: replacements, mockType: mockType, factoryIsolation: configurationIsolation)))
            } else if let variable = item.decl.as(VariableDeclSyntax.self) {
                result.append(contentsOf: PropertyMember.make(variable, index: index, access: access, replacements: replacements, mockType: mockType, factoryIsolation: configurationIsolation).map(GeneratedMember.property))
            } else if let subscriptDecl = item.decl.as(SubscriptDeclSyntax.self) {
                result.append(contentsOf: SubscriptMember.make(subscriptDecl, index: index, access: access, replacements: replacements, mockType: mockType, factoryIsolation: configurationIsolation).map(GeneratedMember.subscriptMember))
            }
        }
        return result
    }

    func validate(in context: some MacroExpansionContext) -> Bool {
        var valid = true
        if protocolDecl.genericWhereClause?.trimmedDescription.contains("~Copyable") == true {
            diagnose("noncopyable associated-type constraints are not supported yet", at: protocolDecl, in: context)
            valid = false
        }
        for item in protocolDecl.memberBlock.members {
            if let associatedType = item.decl.as(AssociatedTypeDeclSyntax.self) {
                if associatedType.trimmedDescription.contains("~Copyable") {
                    diagnose("noncopyable associated types are not supported yet", at: associatedType, in: context)
                    valid = false
                }
                continue
            }
            if let function = item.decl.as(FunctionDeclSyntax.self) {
                let transient = hasAttribute(named: "MockNoncopyable", in: function.attributes) || function.trimmedDescription.contains("~Copyable")
                if transient, function.signature.parameterClause.parameters.contains(where: {
                    $0.type.trimmedDescription.contains("->") && !$0.trimmedDescription.contains("@escaping")
                }) {
                    diagnose("nonescaping closure parameters are not supported on noncopyable requirements", at: function, in: context)
                    valid = false
                } else if transient, function.signature.parameterClause.parameters.count > 1,
                   function.signature.parameterClause.parameters.contains(where: { $0.type.trimmedDescription.hasPrefix("borrowing ") }) {
                    diagnose("Swift 6.3 cannot form a transient aggregate containing a borrowed noncopyable parameter; use a single wrapper parameter", at: function, in: context)
                    valid = false
                } else if transient, function.signature.parameterClause.parameters.count > 1, function.genericParameterClause != nil {
                    diagnose("generic multiargument noncopyable requirements are not supported yet; use a named wrapper parameter", at: function, in: context)
                    valid = false
                } else if function.genericParameterClause?.parameters.contains(where: { $0.specifier != nil }) == true,
                   !(function.signature.parameterClause.parameters.count == 1 && function.signature.parameterClause.parameters.first?.type.trimmedDescription.hasPrefix("repeat each ") == true) {
                    diagnose("parameter packs currently require one pack parameter", at: function, in: context)
                    valid = false
                } else if function.signature.returnClause?.type.trimmedDescription.contains("some ") == true {
                    diagnose("opaque result types are not valid protocol requirements", at: function, in: context)
                    valid = false
                }
                continue
            }
            if let initializer = item.decl.as(InitializerDeclSyntax.self) {
                if initializer.signature.parameterClause.parameters.contains(where: {
                    $0.type.trimmedDescription.contains("->") && !$0.trimmedDescription.contains("@escaping")
                }) {
                    diagnose("nonescaping initializer closures cannot be recorded", at: initializer, in: context)
                    valid = false
                }
                continue
            }
            if let variable = item.decl.as(VariableDeclSyntax.self) {
                if PropertyMember.isSupported(variable) {
                    continue
                }
            }
            if let subscriptDecl = item.decl.as(SubscriptDeclSyntax.self) {
                let settable = (subscriptDecl.accessorBlock?.trimmedDescription ?? "{ get }").contains("set")
                let hasValuePack = subscriptDecl.genericParameterClause?.parameters.contains(where: { $0.specifier != nil }) == true
                let transient = hasAttribute(named: "MockNoncopyable", in: subscriptDecl.attributes) || subscriptDecl.trimmedDescription.contains("~Copyable")
                if transient, subscriptDecl.parameterClause.parameters.contains(where: {
                    $0.type.trimmedDescription.contains("->") && !$0.trimmedDescription.contains("@escaping")
                }) {
                    diagnose("nonescaping closure parameters are not supported on noncopyable requirements", at: subscriptDecl, in: context)
                    valid = false
                    continue
                }
                if settable, hasValuePack {
                    diagnose("settable parameter-pack subscripts are not supported yet", at: subscriptDecl, in: context)
                    valid = false
                    continue
                }
                let transientFieldCount = subscriptDecl.parameterClause.parameters.count + (settable ? 1 : 0)
                if transient, subscriptDecl.genericParameterClause != nil, transientFieldCount > 1 {
                    diagnose("generic multiargument noncopyable subscripts cannot form a transient argument aggregate", at: subscriptDecl, in: context)
                    valid = false
                    continue
                }
                if SubscriptMember.isSupported(subscriptDecl) {
                    continue
                }
            }
            diagnose("@Mockable supports associated types, methods, properties, subscripts, and initializers", at: item.decl, in: context)
            valid = false
        }
        return valid
    }

    func render() -> String {
        let name = protocolDecl.name.text
        let associated = associatedTypes
        let genericParts = associated.map { declaration -> String in
            let inherited = declaration.inheritanceClause?.inheritedTypes.map(\.type.trimmedDescription).joined(separator: " & ")
            let genericName = replacements[declaration.name.text]!
            return genericName + (inherited.map { ": \(rewriteType($0, replacements: replacements, mockType: mockType))" } ?? "")
        }
        let generics = genericParts.isEmpty ? "" : "<\(genericParts.joined(separator: ", "))>"
        let whereRequirements = associated.compactMap(\.genericWhereClause?.requirements.trimmedDescription)
            + [protocolDecl.genericWhereClause?.requirements.trimmedDescription].compactMap { $0 }
        let combinedWhere = whereRequirements.joined(separator: ", ")
        let mockWhere = combinedWhere.isEmpty ? "" : " where " + rewriteType(combinedWhere, replacements: replacements, mockType: mockType)
        let typealiases = associated.map { "    \(access)typealias \($0.name.text) = \(replacements[$0.name.text]!)" }.joined(separator: "\n")
        let typealiasSection = typealiases.isEmpty ? "" : typealiases + "\n\n"
        let availability = protocolDecl.attributes.compactMap { element -> String? in
            guard let attribute = element.as(AttributeSyntax.self) else { return nil }
            let name = attribute.attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
            return name == "available" || (name.hasSuffix("Actor") && name != "Mockable") ? attribute.trimmedDescription : nil
        }.joined(separator: "\n")
        let attributePrefix = availability.isEmpty ? "" : availability + "\n"
        let kind = isActor ? "actor" : "class"
        let isolation = configurationIsolation
        let all = members
        let initializers = protocolDecl.memberBlock.members.enumerated().compactMap { index, item in
            item.decl.as(InitializerDeclSyntax.self).map {
                InitializerMember(declaration: $0, index: index, access: access, replacements: replacements, mockType: mockType, factoryIsolation: configurationIsolation, isActor: isActor, isObjectiveC: isObjectiveC)
            }
        }
        let instance = all.filter { !$0.isStatic }
        let staticMembers = all.filter(\.isStatic)
        let genericMembers = instance.filter(\.usesRegistry)
        let memberChannels = all.filter { !$0.usesRegistry }.map { member in
            if member.isStatic {
                return "    \(isolation)private static var \(member.channelName): \(member.channelType) {\n        StaticMockRegistry.shared.member(owner: Self.self, key: \"\(member.channelName)\") { \(member.channelConstructor) }\n    }"
            }
            return "    \(isolation)private let \(member.channelName) = \(member.channelConstructor)"
        }
        let ephemeralChannels = all.compactMap(\.ephemeralChannelDeclaration)
        let initializerChannels = initializers.filter { !$0.usesRegistry }.map { "    \(isolation)private let \($0.channelName) = \($0.channelType)(name: \"\($0.displayName)\")" }
        let argumentStructs = all.compactMap(\.argumentsStructDeclaration)
        let channels = (argumentStructs + memberChannels + ephemeralChannels + initializerChannels).joined(separator: "\n")
        let initializerWitnesses = initializers.map(\.witness).joined(separator: "\n\n")
        let memberWitnesses = all.map(\.witness).filter { !$0.isEmpty }
        let witnesses = (memberWitnesses + (initializerWitnesses.isEmpty ? [] : [initializerWitnesses])).joined(separator: "\n\n")
        let givenFactories = instance.map(\.givenFactory).joined(separator: "\n\n")
        let verifyFactories = (instance.map(\.verifyFactory) + initializers.map(\.verifyFactory)).joined(separator: "\n\n")
        let performFactories = instance.map(\.performFactory).joined(separator: "\n\n")
        let staticGivenFactories = staticMembers.map(\.givenFactory).joined(separator: "\n\n")
        let staticVerifyFactories = staticMembers.map(\.verifyFactory).joined(separator: "\n\n")
        let staticPerformFactories = staticMembers.map(\.performFactory).joined(separator: "\n\n")
        let resets = (instance.filter { !$0.usesRegistry }.map { "        \($0.channelName).reset(scopes)" } + instance.compactMap(\.ephemeralReset) + initializers.filter { !$0.usesRegistry }.map { "        \($0.channelName).reset(scopes)" }).joined(separator: "\n")
        let channelSection = channels.isEmpty ? "" : channels + "\n\n"
        let givenSection = givenFactories.isEmpty ? "" : "\n\n" + givenFactories
        let verifySection = verifyFactories.isEmpty ? "" : "\n\n" + verifyFactories
        let performSection = performFactories.isEmpty ? "" : "\n\n" + performFactories
        let witnessSection = witnesses.isEmpty ? "" : "\n\n" + witnesses
        let resetSection = resets.isEmpty ? "" : "\n" + resets + "\n    "
        let needsGenericRegistry = !genericMembers.isEmpty || initializers.contains(where: \.usesRegistry)
        let genericRegistry = needsGenericRegistry ? "    \(isolation)private let _genericMockRegistry = GenericMockRegistry()\n\n" : ""
        let staticConformance = staticMembers.isEmpty ? "" : ", StaticMock"
        let staticDSL = staticMembers.isEmpty ? "" : """


            \(access)struct StaticGiven {
                fileprivate let apply: (\(name)Mock.Type) -> Void

        \(staticGivenFactories)
            }

            \(access)struct StaticVerify {
                fileprivate let apply: (\(name)Mock.Type, Count) -> VerificationResult

        \(staticVerifyFactories)
            }

            \(access)struct StaticPerform {
                fileprivate let apply: (\(name)Mock.Type) -> Void

        \(staticPerformFactories)
            }

            \(access)\(isolation)static func given(_ given: StaticGiven) { given.apply(self) }
            \(access)\(isolation)static func perform(_ perform: StaticPerform) { perform.apply(self) }
            \(access)\(isolation)static func verification(_ verify: StaticVerify, count: Count) -> VerificationResult {
                verify.apply(self, count)
            }
            \(access)\(isolation)static func resetMock(_ scopes: MockScope...) {
                StaticMockRegistry.shared.reset(owner: Self.self, scopes: scopes)
            }
        """

        let superclass = isObjectiveC ? "Foundation.NSObject, " : ""
        return attributePrefix + access + "final \(kind) \(name)Mock\(generics): \(superclass)\(name), Mock\(staticConformance)\(mockWhere) {\n"
            + typealiasSection
            + genericRegistry
            + channelSection
            + "    \(access)struct Given {\n"
            + "        fileprivate let apply: (\(name)Mock) -> Void\(givenSection)\n"
            + "    }\n\n"
            + "    \(access)struct Verify {\n"
            + "        fileprivate let apply: (\(name)Mock, Count) -> VerificationResult\(verifySection)\n"
            + "    }\n\n"
            + "    \(access)struct Perform {\n"
            + "        fileprivate let apply: (\(name)Mock) -> Void\(performSection)\n"
            + "    }\n\n"
            + "    \(access)\(isolation)func given(_ given: Given) {\n        given.apply(self)\n    }\n"
            + "    \(access)\(isolation)func perform(_ perform: Perform) {\n        perform.apply(self)\n    }\n"
            + "    \(access)\(isolation)func verification(_ verify: Verify, count: Count) -> VerificationResult {\n"
            + "        verify.apply(self, count)\n    }\n"
            + "    \(access)\(isolation)func resetMock(_ scopes: MockScope...) {\(resetSection)\(needsGenericRegistry ? "\n        _genericMockRegistry.reset(scopes)" : "")\n    }"
            + staticDSL
            + witnessSection + "\n}"
    }

    func supportingMembers() -> [DeclSyntax] {
        let declaration = DeclSyntax(stringLiteral: render())
        let members: MemberBlockItemListSyntax
        if let classDecl = declaration.as(ClassDeclSyntax.self) {
            members = classDecl.memberBlock.members
        } else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
            members = actorDecl.memberBlock.members
        } else {
            return []
        }
        return members.compactMap { item in
            if let variable = item.decl.as(VariableDeclSyntax.self),
               let identifier = variable.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
               identifier.hasPrefix("_mock_") || identifier == "_genericMockRegistry" { return item.decl }
            if let structure = item.decl.as(StructDeclSyntax.self),
               ["Given", "Verify", "Perform", "StaticGiven", "StaticVerify", "StaticPerform"].contains(structure.name.text) { return item.decl }
            if let function = item.decl.as(FunctionDeclSyntax.self),
               ["given", "perform", "verification", "resetMock"].contains(function.name.text) { return item.decl }
            return nil
        }
    }

}

private enum GeneratedMember {
    case function(FunctionMember)
    case property(PropertyMember)
    case subscriptMember(SubscriptMember)

    var channelName: String { switch self { case .function(let x): x.channelName; case .property(let x): x.channelName; case .subscriptMember(let x): x.channelName } }
    var displayName: String { switch self { case .function(let x): x.displayName; case .property(let x): x.displayName; case .subscriptMember(let x): x.displayName } }
    var argumentsType: String { switch self { case .function(let x): x.argumentsType; case .property(let x): x.argumentsType; case .subscriptMember(let x): x.argumentsType } }
    var outputType: String { switch self { case .function(let x): x.outputType; case .property(let x): x.outputType; case .subscriptMember(let x): x.outputType } }
    var isTransient: Bool { switch self { case .function(let x): x.isTransient; case .property(let x): x.isTransient; case .subscriptMember(let x): x.isTransient } }
    var channelType: String { "\(isTransient ? "TransientMockMember" : "MockMember")<\(argumentsType), \(outputType)>" }
    var channelConstructor: String { "\(channelType)(name: \"\(displayName)\")" }
    var isStatic: Bool { switch self { case .function(let x): x.isStatic; case .property(let x): x.isStatic; case .subscriptMember(let x): x.isStatic } }
    var isGeneric: Bool { switch self { case .function(let x): x.isGeneric; case .property: false; case .subscriptMember(let x): x.isGeneric } }
    var usesRegistry: Bool { switch self { case .function(let x): x.usesRegistry; case .property(let x): x.usesRegistry; case .subscriptMember(let x): x.usesRegistry } }
    var witness: String { switch self { case .function(let x): x.witness; case .property(let x): x.witness; case .subscriptMember(let x): x.witness } }
    var givenFactory: String { switch self { case .function(let x): x.givenFactory; case .property(let x): x.givenFactory; case .subscriptMember(let x): x.givenFactory } }
    var verifyFactory: String { switch self { case .function(let x): x.verifyFactory; case .property(let x): x.verifyFactory; case .subscriptMember(let x): x.verifyFactory } }
    var performFactory: String { switch self { case .function(let x): x.performFactory; case .property(let x): x.performFactory; case .subscriptMember(let x): x.performFactory } }
    var ephemeralChannelDeclaration: String? { if case .function(let value) = self { value.ephemeralChannelDeclaration } else { nil } }
    var ephemeralReset: String? { if case .function(let value) = self, value.hasEphemeralDispatcher, !value.ephemeralUsesRegistry { "        \(value.ephemeralChannelName).reset(scopes)" } else { nil } }
    var argumentsStructDeclaration: String? { switch self { case .function(let value): value.argumentsStructDeclaration; case .subscriptMember(let value): value.argumentsStructDeclaration; case .property: nil } }
}

private struct ParameterInfo {
    let external: String
    let local: String
    let type: String
    let matcher: String
    let position: Int

    var isPack: Bool { type.hasPrefix("repeat each ") }
    var packElement: String { isPack ? String(type.dropFirst("repeat ".count)) : type }
    var declaration: String { "\(external == "_" ? "_" : external) \(matcher): \(isPack ? "repeat Parameter<\(packElement)>" : "Parameter<\(type)>")" }
    var actionDeclaration: String { "\(external == "_" ? "_" : external) \(local): \(type)" }
    var argumentAccess: String { position == 0 ? "arguments" : "arguments.\(position)" }
}

private struct FunctionMember {
    let declaration: FunctionDeclSyntax
    let index: Int
    let access: String
    let replacements: [String: String]
    let mockType: String
    let factoryIsolation: String

    var name: String { declaration.name.text }
    var channelName: String { "_mock_\(name.replacingOccurrences(of: "`", with: ""))_\(index)" }
    var displayName: String { declaration.name.text + declaration.signature.parameterClause.parameters.map { "\($0.firstName.text):" }.joined() }
    var parameters: [ParameterInfo] {
        declaration.signature.parameterClause.parameters.enumerated().compactMap { position, parameter in
            if parameter.type.trimmedDescription.contains("->") && !parameter.trimmedDescription.contains("@escaping") {
                return nil
            }
            let external = parameter.firstName.text
            let local = parameter.secondName?.text ?? (external == "_" ? "argument\(position)" : external)
            var type = opaqueParameter(at: position)?.name ?? rewriteType(parameter.type.trimmedDescription, replacements: replacements, mockType: mockType)
            if parameter.ellipsis != nil { type = "[\(type)]" }
            for prefix in ["inout ", "borrowing ", "consuming ", "sending "] where type.hasPrefix(prefix) {
                type.removeFirst(prefix.count)
            }
            return ParameterInfo(external: external, local: local, type: type, matcher: "matching\(position)", position: position)
        }
    }
    var ephemeralParameters: [(local: String, type: String)] {
        declaration.signature.parameterClause.parameters.enumerated().compactMap { position, parameter -> (String, String)? in
            guard parameter.type.trimmedDescription.contains("->"), !parameter.trimmedDescription.contains("@escaping") else { return nil }
            let external = parameter.firstName.text
            let local = parameter.secondName?.text ?? (external == "_" ? "argument\(position)" : external)
            return (local, rewriteType(parameter.type.trimmedDescription, replacements: replacements, mockType: mockType))
        }
    }
    var hasEphemeralDispatcher: Bool { !ephemeralParameters.isEmpty }
    var ephemeralUsesRegistry: Bool { usesRegistry || isStatic }
    var ephemeralChannelName: String { channelName + "_ephemeral" }
    var ephemeralChannelDeclaration: String? {
        guard hasEphemeralDispatcher, !ephemeralUsesRegistry else { return nil }
        return "    private let \(ephemeralChannelName) = EphemeralActionDispatcher<\(argumentsType), \(ephemeralArgumentsType)>()"
    }
    var ephemeralArgumentsType: String {
        if ephemeralParameters.count == 1 { return ephemeralParameters[0].type }
        return "(" + ephemeralParameters.map { "\($0.local): \($0.type)" }.joined(separator: ", ") + ")"
    }
    var ephemeralType: String { "EphemeralActionDispatcher<\(argumentsType), \(ephemeralArgumentsType)>" }
    func ephemeralRegistryResolution(owner: String, indentation: String) -> String {
        guard hasEphemeralDispatcher, ephemeralUsesRegistry else { return "" }
        if isStatic {
            return "let dispatcher: \(ephemeralType) = StaticMockRegistry.shared.member(owner: \(owner), key: \"\(ephemeralChannelName)\", typeIDs: \(registryTypes)) { \(ephemeralType)() }\n\(indentation)"
        }
        return "let dispatcher: \(ephemeralType) = \(owner)._genericMockRegistry.member(key: \"\(ephemeralChannelName)\", typeIDs: \(registryTypes)) { \(ephemeralType)() }\n\(indentation)"
    }
    var argumentsType: String {
        if isTransient, parameters.count > 1 { return "_MockArguments_\(stableIdentifier(displayName))" }
        if parameters.count == 1, parameters[0].isPack { return "(\(parameters[0].type))" }
        return switch parameters.count {
        case 0: "Void"
        case 1: parameters[0].type
        default: "(" + parameters.map { "\($0.local): \($0.type)" }.joined(separator: ", ") + ")"
        }
    }
    var argumentsExpression: String {
        if isTransient, parameters.count > 1 { return "\(argumentsType)(" + parameters.map { "\($0.local): \($0.local)" }.joined(separator: ", ") + ")" }
        if parameters.count == 1, parameters[0].isPack { return "(repeat each \(parameters[0].local))" }
        return switch parameters.count {
        case 0: "()"
        case 1: parameters[0].local
        default: "(" + parameters.map { "\($0.local): \($0.local)" }.joined(separator: ", ") + ")"
        }
    }
    var outputType: String { declaration.signature.returnClause.map { rewriteType($0.type.trimmedDescription, replacements: replacements, mockType: mockType) } ?? "Void" }
    var isStatic: Bool { declaration.modifiers.contains { ["static", "class"].contains($0.name.text) } }
    var opaqueParameters: [(name: String, constraint: String)] {
        declaration.signature.parameterClause.parameters.enumerated().compactMap { position, parameter in
            let type = parameter.type.trimmedDescription
            guard type.hasPrefix("some ") else { return nil }
            return ("_MockOpaque\(position)", String(type.dropFirst(5)))
        }
    }
    func opaqueParameter(at position: Int) -> (name: String, constraint: String)? {
        opaqueParameters.first { $0.name == "_MockOpaque\(position)" }
    }
    var isGeneric: Bool { declaration.genericParameterClause != nil || !opaqueParameters.isEmpty }
    var availability: String { availabilityAttributes(declaration.attributes) }
    var usesRegistry: Bool { isGeneric || !availability.isEmpty }
    var isRethrows: Bool { (declaration.signature.effectSpecifiers?.trimmedDescription ?? "").contains("rethrows") }
    var isThrowing: Bool { (declaration.signature.effectSpecifiers?.trimmedDescription ?? "").contains("throws") }
    var isTransient: Bool { hasAttribute(named: "MockNoncopyable", in: declaration.attributes) || declaration.trimmedDescription.contains("~Copyable") }
    var genericClause: String {
        let explicit = declaration.genericParameterClause?.parameters.map(\.trimmedDescription) ?? []
        let opaque = opaqueParameters.map { "\($0.name): \($0.constraint)" }
        let all = explicit + opaque
        return all.isEmpty ? "" : "<\(all.joined(separator: ", "))>"
    }
    var whereClause: String { declaration.genericWhereClause.map { " " + rewriteType($0.trimmedDescription, replacements: replacements, mockType: mockType) } ?? "" }
    var genericTypes: String {
        ((declaration.genericParameterClause?.parameters.filter { $0.specifier == nil }.map { "\($0.name.text).self" } ?? []) + opaqueParameters.map { "\($0.name).self" }).joined(separator: ", ")
    }
    var packGenericNames: [String] { declaration.genericParameterClause?.parameters.compactMap { $0.specifier == nil ? nil : $0.name.text } ?? [] }
    var registrySetup: String {
        guard !packGenericNames.isEmpty else { return "" }
        var value = "var specializationTypeIDs: [ObjectIdentifier] = \(objectIdentifierList(genericTypes))\n            "
        for name in packGenericNames { value += "for type in repeat (each \(name)).self { specializationTypeIDs.append(ObjectIdentifier(type)) }\n            " }
        return value
    }
    var registryTypes: String { packGenericNames.isEmpty ? objectIdentifierList(genericTypes) : "specializationTypeIDs" }
    var registryResolution: String {
        guard usesRegistry else { return "" }
        if isStatic {
            return "\(registrySetup)let member: \(channelType) = StaticMockRegistry.shared.member(owner: mock, key: \"\(channelName)\", typeIDs: \(registryTypes)) { \(channelConstructor) }\n            "
        }
        return "\(registrySetup)let member: \(channelType) = mock._genericMockRegistry.member(key: \"\(channelName)\", typeIDs: \(registryTypes)) { \(channelConstructor) }\n            "
    }
    var witnessRegistryResolution: String {
        guard usesRegistry else { return "" }
        if isStatic {
            return "\(registrySetup.replacingOccurrences(of: "            ", with: "        "))let member: \(channelType) = StaticMockRegistry.shared.member(owner: Self.self, key: \"\(channelName)\", typeIDs: \(registryTypes)) { \(channelConstructor) }\n        "
        }
        return "\(registrySetup.replacingOccurrences(of: "            ", with: "        "))let member: \(channelType) = _genericMockRegistry.member(key: \"\(channelName)\", typeIDs: \(registryTypes)) { \(channelConstructor) }\n        "
    }
    var channelType: String { "\(isTransient ? "TransientMockMember" : "MockMember")<\(argumentsType), \(outputType)>" }
    var channelConstructor: String { "\(channelType)(name: \"\(displayName)\")" }
    var channelReference: String { usesRegistry ? "member" : "mock.\(channelName)" }
    var argumentsStructDeclaration: String? {
        guard isTransient, parameters.count > 1 else { return nil }
        return "    private struct \(argumentsType): ~Copyable {\n" + parameters.map { "        let \($0.local): \($0.type)" }.joined(separator: "\n") + "\n    }"
    }
    var typedError: String? {
        let effects = declaration.signature.effectSpecifiers?.trimmedDescription ?? ""
        guard let start = effects.range(of: "throws("), let end = effects[start.upperBound...].firstIndex(of: ")") else { return nil }
        let type = String(effects[start.upperBound..<end]).trimmingCharacters(in: .whitespaces)
        return ["Error", "any Error", "any Swift.Error"].contains(type) ? nil : type
    }
    var matcherDeclarations: String { parameters.map(\.declaration).joined(separator: ", ") }
    var matcherClosure: String {
        guard !parameters.isEmpty else { return "{ _ in true }" }
        if parameters.count == 1, let parameter = parameters.first, parameter.isPack {
            return "{ arguments in var result = true; for (argument, matcher) in repeat (each arguments, each \(parameter.matcher)) { result = result && matcher.matches(argument) }; return result }"
        }
        return "{ arguments in " + parameters.map { parameter in
            let access = parameters.count == 1 ? "arguments" : "arguments.\(parameter.local)"
            return "\(parameter.matcher).matches(\(access))"
        }.joined(separator: " && ") + " }"
    }
    var specificity: String {
        if parameters.count == 1, parameters[0].isPack { return "specificity" }
        return parameters.isEmpty ? "0" : parameters.map { "\($0.matcher).specificity" }.joined(separator: " + ")
    }
    var matcherSetup: String {
        guard parameters.count == 1, let parameter = parameters.first, parameter.isPack else { return "" }
        return "var specificity = 0\n            for matcher in repeat each \(parameter.matcher) { specificity += matcher.specificity }\n            "
    }
    var actionType: String {
        let ownership = isTransient ? "borrowing " : ""
        return switch parameters.count {
        case 0: "() -> Void"
        case 1 where parameters[0].isPack: "(\(parameters[0].type)) -> Void"
        case 1: "(\(ownership)\(parameters[0].type)) -> Void"
        default: "(" + parameters.map { ownership + $0.type }.joined(separator: ", ") + ") -> Void"
        }
    }
    var actionCall: String {
        switch parameters.count {
        case 0: "action()"
        case 1 where parameters[0].isPack: "action(repeat each arguments)"
        case 1: "action(arguments)"
        default: "action(" + parameters.map { "arguments.\($0.local)" }.joined(separator: ", ") + ")"
        }
    }
    var signaturePrefix: String {
        let modifiers = declaration.modifiers.compactMap { modifier -> String? in
            if ["mutating", "nonmutating", "optional"].contains(modifier.name.text) { return nil }
            return modifier.name.text == "class" ? "static" : modifier.trimmedDescription
        }.joined(separator: " ")
        return (access + (modifiers.isEmpty ? "" : modifiers + " "))
    }
    var witness: String {
        var signatureText = rewriteType(declaration.signature.trimmedDescription, replacements: replacements, mockType: mockType)
        for opaque in opaqueParameters {
            if let range = signatureText.range(of: "some \(opaque.constraint)") { signatureText.replaceSubrange(range, with: opaque.name) }
        }
        let signature = "\(signaturePrefix)func \(declaration.name.trimmedDescription)\(genericClause)\(signatureText)\(whereClause)"
        let invocation = "\(usesRegistry ? "member" : channelName).invoke(\(argumentsExpression))"
        let ephemeralDispatch: String = {
            guard hasEphemeralDispatcher else { return "" }
            let resolution = ephemeralRegistryResolution(owner: isStatic ? "Self.self" : "self", indentation: "        ")
            let dispatcher = ephemeralUsesRegistry ? "dispatcher" : ephemeralChannelName
            let value = ephemeralParameters.count == 1 ? "_ephemeral0" : "(" + ephemeralParameters.enumerated().map { "\($0.element.local): _ephemeral\($0.offset)" }.joined(separator: ", ") + ")"
            var dispatch = "\(dispatcher).dispatch(\(argumentsExpression), ephemeral: \(value))"
            for (offset, parameter) in ephemeralParameters.enumerated().reversed() {
                dispatch = "withoutActuallyEscaping(\(parameter.local)) { _ephemeral\(offset) in\n            \(dispatch)\n        }"
            }
            return "\(resolution)\(dispatch)\n        "
        }()
        let attributes = witnessAttributePrefix(declaration.attributes, indentation: "    ")
        if let typedError {
            return availabilityPrefix(indentation: "    ") + attributes + """
                \(signature) {
                    \(witnessRegistryResolution)\(ephemeralDispatch)\
                    do { return try \(invocation) }
                    catch let error as \(typedError) { throw error }
                    catch { preconditionFailure("Invalid or unstubbed typed-throws member \(displayName): \\(error)") }
                }
            """.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n")
        }
        if isRethrows {
            return availabilityPrefix(indentation: "    ") + attributes + """
                \(signature) {
                    \(witnessRegistryResolution)\(ephemeralDispatch)\
                    do { return try \(invocation) }
                    catch { preconditionFailure("Invalid or unstubbed rethrows member \(displayName): \\(error)") }
                }
            """.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n")
        }
        if isThrowing { return availabilityPrefix(indentation: "    ") + attributes + "    \(signature) {\n        \(witnessRegistryResolution)\(ephemeralDispatch)try \(invocation)\n    }" }
        return availabilityPrefix(indentation: "    ") + attributes + """
            \(signature) {
                \(witnessRegistryResolution)\(ephemeralDispatch)do { return try \(invocation) }
                catch { preconditionFailure("Unstubbed nonthrowing member \(displayName): \\(error)") }
            }
        """.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n")
    }
    var givenFactory: String {
        let leading = matcherDeclarations.isEmpty ? "" : matcherDeclarations + ", "
        if isTransient {
            let returns: String
            if outputType == "Void" {
                returns = factory(factorySignature(arguments: matcherDeclarations), body: "\(registryResolution)\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: [.producing { () }])")
            } else {
                returns = factory(factorySignature(arguments: "\(leading)willProduce producers: (() -> \(outputType))..."), body: "\(registryResolution)\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: producers.map(TransientStubOutcome<\(outputType)>.producing))")
            }
            guard isThrowing && !isRethrows else { return returns }
            let errorType = typedError ?? "any Error"
            let throwsFactory = factory(factorySignature(arguments: "\(leading)willThrow errors: \(errorType)..."), body: "\(registryResolution)\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: errors.map(TransientStubOutcome<\(outputType)>.throwing))")
            return returns + "\n\n" + throwsFactory
        }
        if outputType == "Void" {
            let returns = factory(factorySignature(arguments: matcherDeclarations), body: "\(registryResolution)\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: [.returnValue(())])")
            guard isThrowing && !isRethrows else { return returns }
            let errorType = typedError ?? "any Error"
            let throwsFactory = factory(factorySignature(arguments: "\(leading)willThrow errors: \(errorType)..."), body: "\(registryResolution)\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: errors.map(StubOutcome.throwError))")
            return returns + "\n\n" + throwsFactory
        }
        let returns = factory(factorySignature(arguments: "\(leading)willReturn values: \(outputType)..."), body: "\(registryResolution)\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: values.map(StubOutcome.returnValue))")
        guard isThrowing && !isRethrows else { return returns }
        let errorType = typedError ?? "any Error"
        let throwsFactory = factory(factorySignature(arguments: "\(leading)willThrow errors: \(errorType)..."), body: "\(registryResolution)\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: errors.map(StubOutcome.throwError))")
        return returns + "\n\n" + throwsFactory
    }
    var verifyFactory: String {
        if isTransient {
            let labels = parameters.filter { $0.external != "_" }.map { "\($0.external): Void = ()" }.joined(separator: ", ")
            return factory(factorySignature(arguments: labels), body: "\(registryResolution)return \(channelReference).verification(count: count)", verify: true)
        }
        return factory(factorySignature(arguments: matcherDeclarations), body: "\(registryResolution)return \(channelReference).verification(matching: \(matcherClosure), count: count)", verify: true)
    }
    var performFactory: String {
        let leading = matcherDeclarations.isEmpty ? "" : matcherDeclarations + ", "
        let outcomes: String
        if outputType == "Void" { outcomes = isTransient ? ", outcomes: [.producing { () }]" : ", outcomes: [.returnValue(())]" }
        else { outcomes = "" }
        let body: String
        if hasEphemeralDispatcher {
            let mainStub = outputType == "Void" ? "\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: [.returnValue(())])\n            " : ""
            let mainResolution = outputType == "Void" ? registryResolution : registrySetup
            let recordableCall: String
            let ephemeralCalls = ephemeralParameters.map { ephemeralParameters.count == 1 ? "ephemeral" : "ephemeral.\($0.local)" }
            switch parameters.count {
            case 0: recordableCall = "action(" + ephemeralCalls.joined(separator: ", ") + ")"
            case 1: recordableCall = "action(" + (["arguments"] + ephemeralCalls).joined(separator: ", ") + ")"
            default: recordableCall = "action(" + (parameters.map { "arguments.\($0.local)" } + ephemeralCalls).joined(separator: ", ") + ")"
            }
            let dispatcherResolution = ephemeralRegistryResolution(owner: isStatic ? "mock" : "mock", indentation: "            ")
            let dispatcher = ephemeralUsesRegistry ? "dispatcher" : "mock.\(ephemeralChannelName)"
            body = "\(mainResolution)\(dispatcherResolution)\(mainStub)\(dispatcher).addAction(matching: \(matcherClosure), specificity: \(specificity)) { arguments, ephemeral in \(recordableCall) }"
            let actionTypes = parameters.map(\.type) + ephemeralParameters.map(\.type)
            let actionType = "(" + actionTypes.joined(separator: ", ") + ") -> Void"
            return factory(factorySignature(arguments: "\(leading)_ action: @escaping \(actionType)"), body: body)
        }
        body = "\(registryResolution)\(channelReference).addAction(matching: \(matcherClosure), specificity: \(specificity)\(outcomes)) { arguments in \(actionCall) }"
        let actionLabel = parameters.contains(where: \.isPack) ? "perform action" : "_ action"
        return factory(factorySignature(arguments: "\(leading)\(actionLabel): @escaping \(actionType)"), body: body)
    }

    private func factorySignature(arguments: String) -> String {
        let genericParameters = (declaration.genericParameterClause?.parameters.map(\.name.text) ?? []) + opaqueParameters.map(\.name)
        var usedReturningLabel = false
        let tokens = genericParameters.compactMap { parameter -> String? in
            guard arguments.range(of: "\\b\(NSRegularExpression.escapedPattern(for: parameter))\\b", options: .regularExpression) == nil else { return nil }
            let appearsInOutput = outputType.range(of: "\\b\(NSRegularExpression.escapedPattern(for: parameter))\\b", options: .regularExpression) != nil
            let label: String
            if appearsInOutput && !usedReturningLabel {
                label = "returning"
                usedReturningLabel = true
            } else {
                label = parameter.prefix(1).lowercased() + String(parameter.dropFirst()) + "Type"
            }
            return "\(label) _: \(parameter).Type"
        }
        let parameters = (tokens + (arguments.isEmpty ? [] : [arguments])).joined(separator: ", ")
        return "\(factoryIsolation)static func \(name)\(genericClause)(\(parameters)) -> Self\(whereClause)"
    }

    private func factory(_ signature: String, body: String, verify: Bool = false) -> String {
        let body = matcherSetup + body
        let closure = verify ? "Self { mock, count in\n            \(body)\n        }" : "Self { mock in\n            \(body)\n        }"
        return availabilityPrefix(indentation: "        ") + """
                \(access)\(signature) {
                    \(closure)
                }
        """
    }

    private func availabilityPrefix(indentation: String) -> String {
        availability.isEmpty ? "" : availability.split(separator: "\n").map { indentation + $0 }.joined(separator: "\n") + "\n"
    }
}

private struct PropertyMember {
    enum Kind { case get, set }
    let name: String
    let type: String
    let kind: Kind
    let index: Int
    let access: String
    let isReadWrite: Bool
    let isStatic: Bool
    let nonisolatedModifier: String
    let factoryIsolation: String
    let getterHeader: String
    let availability: String
    let witnessAttributes: String
    let isTransient: Bool
    var usesRegistry: Bool { !availability.isEmpty }

    static func isSupported(_ declaration: VariableDeclSyntax) -> Bool {
        guard declaration.bindings.count == 1, let binding = declaration.bindings.first,
              binding.pattern.is(IdentifierPatternSyntax.self), binding.typeAnnotation != nil else { return false }
        return true
    }

    static func make(_ declaration: VariableDeclSyntax, index: Int, access: String, replacements: [String: String], mockType: String, factoryIsolation: String) -> [Self] {
        guard isSupported(declaration), let binding = declaration.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self), let annotation = binding.typeAnnotation else { return [] }
        let text = binding.accessorBlock?.trimmedDescription ?? "{ get }"
        let settable = text.contains("set")
        let isStatic = declaration.modifiers.contains { ["static", "class"].contains($0.name.text) }
        let nonisolatedModifier = declaration.modifiers.first(where: { $0.name.text == "nonisolated" })?.trimmedDescription ?? ""
        let type = rewriteType(annotation.type.trimmedDescription, replacements: replacements, mockType: mockType)
        let accessors: [AccessorDeclSyntax] = {
            guard let block = binding.accessorBlock, case .accessors(let list) = block.accessors else { return [] }
            return Array(list)
        }()
        let getterHeader = accessors.first(where: { $0.accessorSpecifier.text == "get" }).map(accessorHeader) ?? "get"
        let availability = availabilityAttributes(declaration.attributes)
        let witnessAttributes = witnessAttributePrefix(declaration.attributes, indentation: "    ")
        let isTransient = hasAttribute(named: "MockNoncopyable", in: declaration.attributes) || declaration.trimmedDescription.contains("~Copyable")
        var result = [Self(name: pattern.identifier.text, type: type, kind: .get, index: index, access: access, isReadWrite: settable, isStatic: isStatic, nonisolatedModifier: nonisolatedModifier, factoryIsolation: factoryIsolation, getterHeader: getterHeader, availability: availability, witnessAttributes: witnessAttributes, isTransient: isTransient)]
        if settable { result.append(Self(name: pattern.identifier.text, type: type, kind: .set, index: index, access: access, isReadWrite: true, isStatic: isStatic, nonisolatedModifier: nonisolatedModifier, factoryIsolation: factoryIsolation, getterHeader: getterHeader, availability: availability, witnessAttributes: witnessAttributes, isTransient: isTransient)) }
        return result
    }

    var suffix: String { kind == .get ? "get" : "set" }
    var channelName: String { "_mock_\(name)_\(suffix)_\(index)" }
    var displayName: String { "\(name).\(suffix)" }
    var argumentsType: String { kind == .get ? "Void" : type }
    var outputType: String { kind == .get ? type : "Void" }
    var getterEffects: String { getterHeader.replacingOccurrences(of: "get", with: "", options: [.anchored]).trimmingCharacters(in: .whitespacesAndNewlines) }
    var isAsync: Bool { getterEffects.range(of: #"\basync\b"#, options: .regularExpression) != nil }
    var isThrowing: Bool { getterEffects.range(of: #"\bthrows\b"#, options: .regularExpression) != nil }
    var typedError: String? { parsedTypedError(getterEffects) }
    var channelType: String { "\(isTransient ? "TransientMockMember" : "MockMember")<\(argumentsType), \(outputType)>" }
    var channelConstructor: String { "\(channelType)(name: \"\(displayName)\")" }
    var registryResolution: String {
        guard usesRegistry else { return "" }
        if isStatic {
            return "let member: \(channelType) = StaticMockRegistry.shared.member(owner: mock, key: \"\(channelName)\", types: []) { \(channelConstructor) }\n            "
        }
        return "let member: \(channelType) = mock._genericMockRegistry.member(key: \"\(channelName)\", types: []) { \(channelConstructor) }\n            "
    }
    var witnessRegistryResolution: String {
        guard usesRegistry else { return "" }
        if isStatic {
            return "let member: \(channelType) = StaticMockRegistry.shared.member(owner: Self.self, key: \"\(channelName)\", types: []) { \(channelConstructor) }\n            "
        }
        return "let member: \(channelType) = _genericMockRegistry.member(key: \"\(channelName)\", types: []) { \(channelConstructor) }\n            "
    }
    var channelReference: String { usesRegistry ? "member" : "mock.\(channelName)" }
    var witnessChannelReference: String { usesRegistry ? "member" : channelName }
    var witness: String {
        guard kind == .get else { return "" }
        let call = "try \(witnessChannelReference).invoke(())"
        let getterBody: String
        if let typedError {
            getterBody = "\(witnessRegistryResolution)do { return \(call) }\n            catch let error as \(typedError) { throw error }\n            catch { preconditionFailure(\"Invalid or unstubbed typed-throws member \(name).get: \\(error)\") }"
        } else if isThrowing {
            getterBody = "\(witnessRegistryResolution)return \(call)"
        } else {
            getterBody = "\(witnessRegistryResolution)do { return \(call) }\n            catch { preconditionFailure(\"Unstubbed nonthrowing member \(name).get: \\(error)\") }"
        }
        let getter = "\(getterHeader) {\n            \(getterBody)\n        }"
        let setterChannel = usesRegistry ? "member" : "_mock_\(name)_set_\(index)"
        let setterResolution: String
        if usesRegistry {
            let setterType = "\(isTransient ? "TransientMockMember" : "MockMember")<\(type), Void>"
            if isStatic { setterResolution = "let member: \(setterType) = StaticMockRegistry.shared.member(owner: Self.self, key: \"_mock_\(name)_set_\(index)\", types: []) { \(setterType)(name: \"\(name).set\") }\n            " }
            else { setterResolution = "let member: \(setterType) = _genericMockRegistry.member(key: \"_mock_\(name)_set_\(index)\", types: []) { \(setterType)(name: \"\(name).set\") }\n            " }
        } else { setterResolution = "" }
        let setter = isReadWrite ? "\n        set {\n            \(setterResolution)do { return try \(setterChannel).invoke(newValue) }\n            catch { preconditionFailure(\"Unstubbed nonthrowing member \(name).set: \\(error)\") }\n        }" : ""
        let prefix = availability.isEmpty ? "" : availability + "\n"
        return prefix + witnessAttributes + "    \(access)\(nonisolatedModifier.isEmpty ? "" : nonisolatedModifier + " ")\(isStatic ? "static " : "")var \(name): \(type) {\n        \(getter)\(setter)\n    }"
    }
    var givenFactory: String {
        switch kind {
        case .get:
            if isTransient {
                let returns = factory("static func \(name)(willProduce producers: (() -> \(type))...) -> Self", "\(registryResolution)\(channelReference).addStub(matching: { _ in true }, specificity: 0, outcomes: producers.map(TransientStubOutcome<\(type)>.producing))")
                guard isThrowing else { return returns }
                let errors = typedError ?? "any Error"
                return returns + "\n\n" + factory("static func \(name)(willThrow errors: \(errors)...) -> Self", "\(registryResolution)\(channelReference).addStub(matching: { _ in true }, specificity: 0, outcomes: errors.map(TransientStubOutcome<\(type)>.throwing))")
            }
            let returns = factory("static func \(name)(willReturn values: \(type)...) -> Self", "\(registryResolution)\(channelReference).addStub(matching: { _ in true }, specificity: 0, outcomes: values.map(StubOutcome.returnValue))")
            guard isThrowing else { return returns }
            let errors = typedError ?? "any Error"
            return returns + "\n\n" + factory("static func \(name)(willThrow errors: \(errors)...) -> Self", "\(registryResolution)\(channelReference).addStub(matching: { _ in true }, specificity: 0, outcomes: errors.map(StubOutcome.throwError))")
        case .set:
            if isTransient { return factory("static func \(name)(set matching: Parameter<\(type)>) -> Self", "\(registryResolution)\(channelReference).addStub(matching: { matching.matches($0) }, specificity: matching.specificity, outcomes: [.producing { () }])") }
            return factory("static func \(name)(set matching: Parameter<\(type)>) -> Self", "\(registryResolution)\(channelReference).addStub(matching: { matching.matches($0) }, specificity: matching.specificity, outcomes: [.returnValue(())])")
        }
    }
    var verifyFactory: String {
        switch kind {
        case .get:
            if isTransient { return verifyFactory("static func \(name)() -> Self", "\(registryResolution)return \(channelReference).verification(count: count)") }
            return verifyFactory("static func \(name)() -> Self", "\(registryResolution)return \(channelReference).verification(matching: { _ in true }, count: count)")
        case .set:
            if isTransient { return verifyFactory("static func \(name)(set: Void = ()) -> Self", "\(registryResolution)return \(channelReference).verification(count: count)") }
            return verifyFactory("static func \(name)(set matching: Parameter<\(type)>) -> Self", "\(registryResolution)return \(channelReference).verification(matching: { matching.matches($0) }, count: count)")
        }
    }
    var performFactory: String {
        switch kind {
        case .get:
            return factory("static func \(name)(_ action: @escaping () -> Void) -> Self", "\(registryResolution)\(channelReference).addAction(matching: { _ in true }, specificity: 0) { _ in action() }")
        case .set:
            if isTransient { return factory("static func \(name)(set matching: Parameter<\(type)>, _ action: @escaping (borrowing \(type)) -> Void) -> Self", "\(registryResolution)\(channelReference).addAction(matching: { matching.matches($0) }, specificity: matching.specificity, outcomes: [.producing { () }], action: action)") }
            return factory("static func \(name)(set matching: Parameter<\(type)>, _ action: @escaping (\(type)) -> Void) -> Self", "\(registryResolution)\(channelReference).addAction(matching: { matching.matches($0) }, specificity: matching.specificity, outcomes: [.returnValue(())], action: action)")
        }
    }

    private func factory(_ signature: String, _ body: String) -> String {
        (availability.isEmpty ? "" : availability.split(separator: "\n").map { "        " + $0 }.joined(separator: "\n") + "\n") + "        \(access)\(factoryIsolation)\(signature) {\n            Self { mock in\n                \(body)\n            }\n        }"
    }
    private func verifyFactory(_ signature: String, _ body: String) -> String {
        (availability.isEmpty ? "" : availability.split(separator: "\n").map { "        " + $0 }.joined(separator: "\n") + "\n") + "        \(access)\(factoryIsolation)\(signature) {\n            Self { mock, count in\n                \(body)\n            }\n        }"
    }
}

private struct SubscriptMember {
    enum Kind { case get, set }
    let declaration: SubscriptDeclSyntax
    let kind: Kind
    let index: Int
    let access: String
    let parameters: [ParameterInfo]
    let valueType: String
    let isReadWrite: Bool
    let factoryIsolation: String
    let replacements: [String: String]
    let mockType: String
    let getterHeader: String
    let availability: String
    let witnessAttributes: String

    var isStatic: Bool { declaration.modifiers.contains { ["static", "class"].contains($0.name.text) } }
    var isGeneric: Bool { declaration.genericParameterClause != nil }
    var isTransient: Bool { hasAttribute(named: "MockNoncopyable", in: declaration.attributes) || declaration.trimmedDescription.contains("~Copyable") }
    var usesRegistry: Bool { isGeneric || !availability.isEmpty }
    var genericTypes: String { declaration.genericParameterClause?.parameters.filter { $0.specifier == nil }.map { "\($0.name.text).self" }.joined(separator: ", ") ?? "" }
    var packGenericNames: [String] { declaration.genericParameterClause?.parameters.compactMap { $0.specifier == nil ? nil : $0.name.text } ?? [] }
    var registrySetup: String {
        guard !packGenericNames.isEmpty else { return "" }
        var value = "var specializationTypeIDs: [ObjectIdentifier] = \(objectIdentifierList(genericTypes))\n            "
        for name in packGenericNames { value += "for type in repeat (each \(name)).self { specializationTypeIDs.append(ObjectIdentifier(type)) }\n            " }
        return value
    }
    var registryTypes: String { packGenericNames.isEmpty ? objectIdentifierList(genericTypes) : "specializationTypeIDs" }

    static func isSupported(_ declaration: SubscriptDeclSyntax) -> Bool {
        true
    }

    static func make(_ declaration: SubscriptDeclSyntax, index: Int, access: String, replacements: [String: String], mockType: String, factoryIsolation: String) -> [Self] {
        guard isSupported(declaration) else { return [] }
        let parameters = declaration.parameterClause.parameters.enumerated().map { position, parameter in
            let external = parameter.firstName.text
            let local = parameter.secondName?.text ?? (external == "_" ? "index\(position)" : external)
            var type = rewriteType(parameter.type.trimmedDescription, replacements: replacements, mockType: mockType)
            if parameter.ellipsis != nil { type = "[\(type)]" }
            return ParameterInfo(external: external, local: local, type: type, matcher: "matching\(position)", position: position)
        }
        let settable = (declaration.accessorBlock?.trimmedDescription ?? "{ get }").contains("set")
        let valueType = rewriteType(declaration.returnClause.type.trimmedDescription, replacements: replacements, mockType: mockType)
        let accessors: [AccessorDeclSyntax] = {
            guard let block = declaration.accessorBlock, case .accessors(let list) = block.accessors else { return [] }
            return Array(list)
        }()
        let getterHeader = accessors.first(where: { $0.accessorSpecifier.text == "get" }).map(accessorHeader) ?? "get"
        let availability = availabilityAttributes(declaration.attributes)
        let witnessAttributes = witnessAttributePrefix(declaration.attributes, indentation: "    ")
        var result = [Self(declaration: declaration, kind: .get, index: index, access: access, parameters: parameters, valueType: valueType, isReadWrite: settable, factoryIsolation: factoryIsolation, replacements: replacements, mockType: mockType, getterHeader: getterHeader, availability: availability, witnessAttributes: witnessAttributes)]
        if settable { result.append(Self(declaration: declaration, kind: .set, index: index, access: access, parameters: parameters, valueType: valueType, isReadWrite: true, factoryIsolation: factoryIsolation, replacements: replacements, mockType: mockType, getterHeader: getterHeader, availability: availability, witnessAttributes: witnessAttributes)) }
        return result
    }

    var signatureIdentifierSource: String {
        let modifiers = declaration.modifiers.map(\.trimmedDescription).filter { !["public", "package", "internal", "fileprivate", "private"].contains($0) }.joined(separator: " ")
        return [modifiers, declaration.genericParameterClause?.trimmedDescription ?? "", declaration.parameterClause.trimmedDescription, declaration.returnClause.trimmedDescription, declaration.genericWhereClause?.trimmedDescription ?? "", getterHeader].joined(separator: "|")
    }
    var channelName: String { "_mock_subscript_\(kind == .get ? "get" : "set")_\(stableIdentifier(signatureIdentifierSource))" }
    var displayName: String { "subscript.\(kind == .get ? "get" : "set")" }
    var argumentsType: String {
        if isTransient, argumentsFieldCount > 1 { return "_MockArguments_\(stableIdentifier(displayName + signatureIdentifierSource))" }
        if kind == .get, parameters.count == 1, parameters[0].isPack { return "(\(parameters[0].type))" }
        let fields = parameters.map { "\($0.local): \($0.type)" } + (kind == .set ? ["newValue: \(valueType)"] : [])
        if fields.isEmpty { return "Void" }
        if fields.count == 1 { return parameters[0].type }
        return "(" + fields.joined(separator: ", ") + ")"
    }
    var outputType: String { kind == .get ? valueType : "Void" }
    var getterEffects: String { getterHeader.replacingOccurrences(of: "get", with: "", options: [.anchored]).trimmingCharacters(in: .whitespacesAndNewlines) }
    var isAsync: Bool { getterEffects.range(of: #"\basync\b"#, options: .regularExpression) != nil }
    var isThrowing: Bool { getterEffects.range(of: #"\bthrows\b"#, options: .regularExpression) != nil }
    var typedError: String? { parsedTypedError(getterEffects) }
    var channelType: String { "\(isTransient ? "TransientMockMember" : "MockMember")<\(argumentsType), \(outputType)>" }
    var channelConstructor: String { "\(channelType)(name: \"\(displayName)\")" }
    var registryResolution: String {
        guard usesRegistry else { return "" }
        if isStatic {
            return "\(registrySetup)let member: \(channelType) = StaticMockRegistry.shared.member(owner: mock, key: \"\(channelName)\", typeIDs: \(registryTypes)) { \(channelConstructor) }\n            "
        }
        return "\(registrySetup)let member: \(channelType) = mock._genericMockRegistry.member(key: \"\(channelName)\", typeIDs: \(registryTypes)) { \(channelConstructor) }\n            "
    }
    var witnessRegistryResolution: String {
        guard usesRegistry else { return "" }
        if isStatic {
            return "\(registrySetup)let member: \(channelType) = StaticMockRegistry.shared.member(owner: Self.self, key: \"\(channelName)\", typeIDs: \(registryTypes)) { \(channelConstructor) }\n            "
        }
        return "\(registrySetup)let member: \(channelType) = _genericMockRegistry.member(key: \"\(channelName)\", typeIDs: \(registryTypes)) { \(channelConstructor) }\n            "
    }
    var channelReference: String { usesRegistry ? "member" : "mock.\(channelName)" }
    var witnessChannelReference: String { usesRegistry ? "member" : channelName }
    var argumentsStructDeclaration: String? {
        guard isTransient, argumentsFieldCount > 1 else { return nil }
        let fields = parameters.map { ($0.local, $0.type) } + (kind == .set ? [("newValue", valueType)] : [])
        return "    private struct \(argumentsType): ~Copyable {\n" + fields.map { "        let \($0.0): \($0.1)" }.joined(separator: "\n") + "\n    }"
    }
    var matcherDeclarations: String {
        let base = parameters.map(\.declaration)
        return (base + (kind == .set ? ["value: Parameter<\(valueType)>"] : [])).joined(separator: ", ")
    }
    var specificity: String {
        if kind == .get, parameters.count == 1, parameters[0].isPack { return "specificity" }
        let parts = parameters.map { "\($0.matcher).specificity" } + (kind == .set ? ["value.specificity"] : [])
        return parts.isEmpty ? "0" : parts.joined(separator: " + ")
    }
    var matcherClosure: String {
        if kind == .get, parameters.count == 1, let parameter = parameters.first, parameter.isPack {
            return "{ arguments in var result = true; for (argument, matcher) in repeat (each arguments, each \(parameter.matcher)) { result = result && matcher.matches(argument) }; return result }"
        }
        var parts = parameters.enumerated().map { position, parameter in
            let argument = argumentsFieldCount == 1 ? "arguments" : "arguments.\(parameter.local)"
            return "\(parameter.matcher).matches(\(argument))"
        }
        if kind == .set { parts.append("value.matches(arguments.newValue)") }
        return parts.isEmpty ? "{ _ in true }" : "{ arguments in " + parts.joined(separator: " && ") + " }"
    }
    var argumentsFieldCount: Int { parameters.count + (kind == .set ? 1 : 0) }
    var invocationArguments: String {
        if isTransient, argumentsFieldCount > 1 {
            let fields = parameters.map { "\($0.local): \($0.local)" } + (kind == .set ? ["newValue: newValue"] : [])
            return "\(argumentsType)(\(fields.joined(separator: ", ")))"
        }
        if kind == .get, parameters.count == 1, parameters[0].isPack { return "(repeat each \(parameters[0].local))" }
        let fields = parameters.map { "\($0.local): \($0.local)" } + (kind == .set ? ["newValue: newValue"] : [])
        if fields.isEmpty { return "()" }
        if fields.count == 1 { return parameters[0].local }
        return "(" + fields.joined(separator: ", ") + ")"
    }
    var witness: String {
        guard kind == .get else { return "" }
        let generics = declaration.genericParameterClause?.trimmedDescription ?? ""
        let whereClause = declaration.genericWhereClause.map { rewriteType($0.trimmedDescription, replacements: replacements, mockType: mockType) } ?? ""
        let call = "try \(witnessChannelReference).invoke(\(invocationArguments))"
        let getterBody: String
        if let typedError {
            getterBody = "\(witnessRegistryResolution)do { return \(call) }\n            catch let error as \(typedError) { throw error }\n            catch { preconditionFailure(\"Invalid or unstubbed typed-throws member subscript.get: \\(error)\") }"
        } else if isThrowing {
            getterBody = "\(witnessRegistryResolution)return \(call)"
        } else {
            getterBody = "\(witnessRegistryResolution)do { return \(call) }\n            catch { preconditionFailure(\"Unstubbed nonthrowing member subscript.get: \\(error)\") }"
        }
        let getter = "\(getterHeader) {\n            \(getterBody)\n        }"
        let setterMember = Self(declaration: declaration, kind: .set, index: index, access: access, parameters: parameters, valueType: valueType, isReadWrite: true, factoryIsolation: factoryIsolation, replacements: replacements, mockType: mockType, getterHeader: getterHeader, availability: availability, witnessAttributes: witnessAttributes)
        let setterArgs = setterMember.invocationArguments
        let setter = isReadWrite ? "\n        set {\n            \(setterMember.witnessRegistryResolution)do { return try \(setterMember.witnessChannelReference).invoke(\(setterArgs)) }\n            catch { preconditionFailure(\"Unstubbed nonthrowing member subscript.set: \\(error)\") }\n        }" : ""
        let parameterClause = rewriteType(declaration.parameterClause.trimmedDescription, replacements: replacements, mockType: mockType)
        let modifiers = declaration.modifiers.map { $0.name.text == "class" ? "static" : $0.trimmedDescription }.filter { !["public", "package", "internal", "fileprivate", "private"].contains($0) }.joined(separator: " ")
        let prefix = availability.isEmpty ? "" : availability + "\n"
        return prefix + witnessAttributes + "    \(access)\(modifiers.isEmpty ? "" : modifiers + " ")subscript\(generics)\(parameterClause) -> \(valueType) \(whereClause){\n        \(getter)\(setter)\n    }"
    }
    var givenFactory: String {
        switch kind {
        case .get:
            let leading = matcherDeclarations.isEmpty ? "" : matcherDeclarations + ", "
            if isTransient {
                let returns = factory("static func subscriptGet\(genericClause)(\(factoryArguments(leading + "willProduce producers: (() -> \(valueType))..."))) -> Self\(whereClause)", "\(registryResolution)\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: producers.map(TransientStubOutcome<\(valueType)>.producing))")
                guard isThrowing else { return returns }
                let errors = typedError ?? "any Error"
                return returns + "\n\n" + factory("static func subscriptGet\(genericClause)(\(factoryArguments(leading + "willThrow errors: \(errors)..."))) -> Self\(whereClause)", "\(registryResolution)\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: errors.map(TransientStubOutcome<\(valueType)>.throwing))")
            }
            let returns = factory("static func subscriptGet\(genericClause)(\(factoryArguments(leading + "willReturn values: \(valueType)..."))) -> Self\(whereClause)", "\(registryResolution)\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: values.map(StubOutcome.returnValue))")
            guard isThrowing else { return returns }
            let errors = typedError ?? "any Error"
            return returns + "\n\n" + factory("static func subscriptGet\(genericClause)(\(factoryArguments(leading + "willThrow errors: \(errors)..."))) -> Self\(whereClause)", "\(registryResolution)\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: errors.map(StubOutcome.throwError))")
        case .set:
            if isTransient { return factory("static func subscriptSet\(genericClause)(\(factoryArguments(matcherDeclarations))) -> Self\(whereClause)", "\(registryResolution)\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: [.producing { () }])") }
            return factory("static func subscriptSet\(genericClause)(\(factoryArguments(matcherDeclarations))) -> Self\(whereClause)", "\(registryResolution)\(channelReference).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: [.returnValue(())])")
        }
    }
    var verifyFactory: String {
        if isTransient {
            return verifyFactory("static func \(kind == .get ? "subscriptGet" : "subscriptSet")\(genericClause)(\(factoryArguments(""))) -> Self\(whereClause)", "\(registryResolution)return \(channelReference).verification(count: count)")
        }
        return verifyFactory("static func \(kind == .get ? "subscriptGet" : "subscriptSet")\(genericClause)(\(factoryArguments(matcherDeclarations))) -> Self\(whereClause)", "\(registryResolution)return \(channelReference).verification(matching: \(matcherClosure), count: count)")
    }
    var performFactory: String {
        let ownership = isTransient ? "borrowing " : ""
        let actionTypes = parameters.map { ownership + $0.type } + (kind == .set ? [ownership + valueType] : [])
        let actionType = "(" + actionTypes.joined(separator: ", ") + ") -> Void"
        let actionArgs = kind == .get && parameters.count == 1 && parameters[0].isPack
            ? ["repeat each arguments"]
            : parameters.map { argumentsFieldCount == 1 ? "arguments" : "arguments.\($0.local)" } + (kind == .set ? ["arguments.newValue"] : [])
        let leading = matcherDeclarations.isEmpty ? "" : matcherDeclarations + ", "
        let outcomes = kind == .set ? (isTransient ? ", outcomes: [.producing { () }]" : ", outcomes: [.returnValue(())]") : ""
        let body = "\(registryResolution)\(channelReference).addAction(matching: \(matcherClosure), specificity: \(specificity)\(outcomes)) { arguments in action(\(actionArgs.joined(separator: ", "))) }"
        let actionLabel = parameters.contains(where: \.isPack) ? "perform action" : "_ action"
        return factory("static func \(kind == .get ? "subscriptGet" : "subscriptSet")\(genericClause)(\(factoryArguments(leading + "\(actionLabel): @escaping \(actionType)"))) -> Self\(whereClause)", body)
    }

    var genericClause: String { declaration.genericParameterClause?.trimmedDescription ?? "" }
    var whereClause: String { declaration.genericWhereClause.map { " " + rewriteType($0.trimmedDescription, replacements: replacements, mockType: mockType) } ?? "" }

    private func factoryArguments(_ arguments: String) -> String {
        var usedReturningLabel = false
        let tokens = declaration.genericParameterClause?.parameters.compactMap { parameter -> String? in
            let name = parameter.name.text
            guard arguments.range(of: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b", options: .regularExpression) == nil else { return nil }
            if parameter.specifier != nil { return "_ types: repeat (each \(name)).Type" }
            let appearsInOutput = valueType.range(of: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b", options: .regularExpression) != nil
            let label = appearsInOutput && !usedReturningLabel
                ? "returning"
                : name.prefix(1).lowercased() + String(name.dropFirst()) + "Type"
            if appearsInOutput { usedReturningLabel = true }
            return "\(label) _: \(name).Type"
        } ?? []
        return (tokens + (arguments.isEmpty ? [] : [arguments])).joined(separator: ", ")
    }

    private func factory(_ signature: String, _ body: String) -> String {
        let setup = packMatcherSetup
        return (availability.isEmpty ? "" : availability.split(separator: "\n").map { "        " + $0 }.joined(separator: "\n") + "\n") + "        \(access)\(factoryIsolation)\(signature) {\n            Self { mock in\n                \(setup)\(body)\n            }\n        }"
    }
    private func verifyFactory(_ signature: String, _ body: String) -> String {
        let setup = packMatcherSetup
        return (availability.isEmpty ? "" : availability.split(separator: "\n").map { "        " + $0 }.joined(separator: "\n") + "\n") + "        \(access)\(factoryIsolation)\(signature) {\n            Self { mock, count in\n                \(setup)\(body)\n            }\n        }"
    }

    var packMatcherSetup: String {
        guard parameters.count == 1, let parameter = parameters.first, parameter.isPack else { return "" }
        return "var specificity = 0\n            for matcher in repeat each \(parameter.matcher) { specificity += matcher.specificity }\n            "
    }
}

private struct InitializerMember {
    let declaration: InitializerDeclSyntax
    let index: Int
    let access: String
    let replacements: [String: String]
    let mockType: String
    let factoryIsolation: String
    let isActor: Bool
    let isObjectiveC: Bool

    var isGeneric: Bool { declaration.genericParameterClause != nil }
    var isTransient: Bool { hasAttribute(named: "MockNoncopyable", in: declaration.attributes) || declaration.trimmedDescription.contains("~Copyable") }
    var channelType: String { "\(isTransient ? "TransientMockMember" : "MockMember")<\(argumentsType), Void>" }
    var availability: String { availabilityAttributes(declaration.attributes) }
    var usesRegistry: Bool { isGeneric || !availability.isEmpty }
    var genericTypes: String {
        declaration.genericParameterClause?.parameters.filter { $0.specifier == nil }.map { "\($0.name.text).self" }.joined(separator: ", ") ?? ""
    }
    var packGenericNames: [String] { declaration.genericParameterClause?.parameters.compactMap { $0.specifier == nil ? nil : $0.name.text } ?? [] }
    var registrySetup: String {
        guard !packGenericNames.isEmpty else { return "" }
        var value = "var specializationTypeIDs: [ObjectIdentifier] = \(objectIdentifierList(genericTypes))\n            "
        for name in packGenericNames { value += "for type in repeat (each \(name)).self { specializationTypeIDs.append(ObjectIdentifier(type)) }\n            " }
        return value
    }
    var registryTypes: String { packGenericNames.isEmpty ? objectIdentifierList(genericTypes) : "specializationTypeIDs" }
    var registryResolution: String {
        guard usesRegistry else { return "" }
        return "\(registrySetup)let member: \(channelType) = mock._genericMockRegistry.member(key: \"\(channelName)\", typeIDs: \(registryTypes)) { \(channelType)(name: \"\(displayName)\") }\n            "
    }
    var witnessRegistryResolution: String {
        guard usesRegistry else { return "" }
        return "\(registrySetup.replacingOccurrences(of: "            ", with: "        "))let member: \(channelType) = _genericMockRegistry.member(key: \"\(channelName)\", typeIDs: \(registryTypes)) { \(channelType)(name: \"\(displayName)\") }\n        "
    }
    var channelReference: String { usesRegistry ? "member" : "mock.\(channelName)" }

    var channelName: String { "_mock_initializer_\(index)" }
    var displayName: String { "init" + declaration.signature.parameterClause.parameters.map { "\($0.firstName.text):" }.joined() }
    var parameters: [ParameterInfo] {
        declaration.signature.parameterClause.parameters.enumerated().map { position, parameter in
            let external = parameter.firstName.text
            let local = parameter.secondName?.text ?? (external == "_" ? "argument\(position)" : external)
            var type = rewriteType(parameter.type.trimmedDescription, replacements: replacements, mockType: mockType)
            if parameter.ellipsis != nil { type = "[\(type)]" }
            for prefix in ["inout ", "borrowing ", "consuming ", "sending "] where type.hasPrefix(prefix) {
                type.removeFirst(prefix.count)
            }
            return ParameterInfo(external: external, local: local, type: type, matcher: "matching\(position)", position: position)
        }
    }
    var argumentsType: String {
        if isTransient { return "Void" }
        if parameters.count == 1, parameters[0].isPack { return "(\(parameters[0].type))" }
        return switch parameters.count {
        case 0: "Void"
        case 1: parameters[0].type
        default: "(" + parameters.map { "\($0.local): \($0.type)" }.joined(separator: ", ") + ")"
        }
    }
    var argumentsExpression: String {
        if parameters.count == 1, parameters[0].isPack { return "(repeat each \(parameters[0].local))" }
        return switch parameters.count {
        case 0: "()"
        case 1: parameters[0].local
        default: "(" + parameters.map { "\($0.local): \($0.local)" }.joined(separator: ", ") + ")"
        }
    }
    var matcherDeclarations: String { parameters.map(\.declaration).joined(separator: ", ") }
    var matcherClosure: String {
        guard !parameters.isEmpty else { return "{ _ in true }" }
        if parameters.count == 1, let parameter = parameters.first, parameter.isPack {
            return "{ arguments in var result = true; for (argument, matcher) in repeat (each arguments, each \(parameter.matcher)) { result = result && matcher.matches(argument) }; return result }"
        }
        return "{ arguments in " + parameters.map { parameter in
            let value = parameters.count == 1 ? "arguments" : "arguments.\(parameter.local)"
            return "\(parameter.matcher).matches(\(value))"
        }.joined(separator: " && ") + " }"
    }
    var witness: String {
        let required = isActor ? "" : "required "
        let override = isObjectiveC && parameters.isEmpty && declaration.optionalMark == nil
            && declaration.signature.effectSpecifiers == nil ? "override " : ""
        let genericClause = declaration.genericParameterClause?.trimmedDescription ?? ""
        let signature = rewriteType(declaration.signature.trimmedDescription, replacements: replacements, mockType: mockType)
        let whereClause = declaration.genericWhereClause.map { " " + rewriteType($0.trimmedDescription, replacements: replacements, mockType: mockType) } ?? ""
        let attributes = declaration.attributes.map(\.trimmedDescription).joined(separator: "\n    ")
        let attributePrefix = attributes.isEmpty ? "" : "    " + attributes + "\n"
        let ignored = Set(["required", "public", "package", "internal", "fileprivate", "private"])
        let modifiers = declaration.modifiers.map(\.name.text).filter { !ignored.contains($0) }.joined(separator: " ")
        let modifierPrefix = modifiers.isEmpty ? "" : modifiers + " "
        let recording = isTransient ? "\(usesRegistry ? "member" : channelName).record()" : "\(usesRegistry ? "member" : channelName).record(\(argumentsExpression))"
        return "\(attributePrefix)    \(access)\(required)\(override)\(modifierPrefix)init\(declaration.optionalMark?.text ?? "")\(genericClause)\(signature)\(whereClause) {\n        \(witnessRegistryResolution)\(recording)\n    }"
    }
    var verifyFactory: String {
        let availabilityPrefix = availability.isEmpty ? "" : availability.split(separator: "\n").map { "        " + $0 }.joined(separator: "\n") + "\n"
        if isTransient {
            let typeTokens = declaration.genericParameterClause?.parameters.map { parameter -> String in
                if parameter.specifier != nil { return "_ types: repeat (each \(parameter.name.text)).Type" }
                let label = parameter.name.text.prefix(1).lowercased() + String(parameter.name.text.dropFirst()) + "Type"
                return "\(label) _: \(parameter.name.text).Type"
            }.joined(separator: ", ") ?? ""
            return availabilityPrefix + """
                    \(access)\(factoryIsolation)static func initializer\(declaration.genericParameterClause?.trimmedDescription ?? "")(\(typeTokens)) -> Self\(declaration.genericWhereClause.map { " " + rewriteType($0.trimmedDescription, replacements: replacements, mockType: mockType) } ?? "") {
                        Self { mock, count in
                            \(registryResolution)return \(channelReference).verification(count: count)
                        }
                    }
            """
        }
        return availabilityPrefix + """
                \(access)\(factoryIsolation)static func initializer\(declaration.genericParameterClause?.trimmedDescription ?? "")(\(matcherDeclarations)) -> Self\(declaration.genericWhereClause.map { " " + rewriteType($0.trimmedDescription, replacements: replacements, mockType: mockType) } ?? "") {
                    Self { mock, count in
                        \(registryResolution)return \(channelReference).verification(matching: \(matcherClosure), count: count)
                    }
                }
        """
    }
}

private struct MacroDiagnostic: DiagnosticMessage {
    let message: String
    var diagnosticID: MessageID { MessageID(domain: "Mock4Swift.Mockable", id: message) }
    var severity: DiagnosticSeverity { .error }
}

private func hasAvailabilityAttribute(_ attributes: AttributeListSyntax) -> Bool {
    attributes.contains { element in
        guard let attribute = element.as(AttributeSyntax.self) else { return false }
        return attribute.attributeName.trimmedDescription.split(separator: ".").last == "available"
    }
}

private func hasAttribute(named expected: String, in attributes: AttributeListSyntax) -> Bool {
    attributes.contains { element in
        guard let attribute = element.as(AttributeSyntax.self) else { return false }
        return attribute.attributeName.trimmedDescription.split(separator: ".").last == Substring(expected)
    }
}

private func availabilityAttributes(_ attributes: AttributeListSyntax) -> String {
    attributes.compactMap { element -> String? in
        guard let attribute = element.as(AttributeSyntax.self),
              attribute.attributeName.trimmedDescription.split(separator: ".").last == "available" else { return nil }
        return attribute.trimmedDescription
    }.joined(separator: "\n")
}

private func witnessAttributePrefix(_ attributes: AttributeListSyntax, indentation: String) -> String {
    let values = attributes.compactMap { element -> String? in
        guard let attribute = element.as(AttributeSyntax.self) else { return nil }
        let name = attribute.attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
        guard !["available", "MockNoncopyable", "MockableAccessor"].contains(name) else { return nil }
        return indentation + attribute.trimmedDescription
    }
    return values.isEmpty ? "" : values.joined(separator: "\n") + "\n"
}

private func accessorHeader(_ accessor: AccessorDeclSyntax) -> String {
    var copy = accessor
    copy.body = nil
    copy.attributes = []
    return copy.trimmedDescription
}

private func parsedTypedError(_ effects: String) -> String? {
    guard let start = effects.range(of: "throws("), let end = effects[start.upperBound...].firstIndex(of: ")") else { return nil }
    let type = String(effects[start.upperBound..<end]).trimmingCharacters(in: .whitespaces)
    return ["Error", "any Error", "any Swift.Error"].contains(type) ? nil : type
}

private func stableIdentifier(_ text: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16)
}

private func objectIdentifierList(_ metatypes: String) -> String {
    let values = metatypes.split(separator: ",").map { "ObjectIdentifier(\($0.trimmingCharacters(in: .whitespaces)))" }
    return "[\(values.joined(separator: ", "))]"
}

private func diagnose(
    _ message: String,
    at node: some SyntaxProtocol,
    in context: some MacroExpansionContext
) {
    context.diagnose(Diagnostic(node: Syntax(node), message: MacroDiagnostic(message: message)))
}

private func rewriteType(_ text: String, replacements: [String: String], mockType: String) -> String {
    var text = text
    for (associated, replacement) in replacements {
        text = text.replacingOccurrences(
            of: #"\bSelf\s*\.\s*"# + NSRegularExpression.escapedPattern(for: associated) + #"\b"#,
            with: replacement,
            options: .regularExpression
        )
    }
    let mapping = replacements.merging(["Self": mockType]) { current, _ in current }
    let names = mapping.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern)
    guard !names.isEmpty,
          let expression = try? NSRegularExpression(pattern: "\\b(?:\(names.joined(separator: "|")))\\b") else { return text }
    let result = NSMutableString(string: text)
    let range = NSRange(location: 0, length: result.length)
    for match in expression.matches(in: text, range: range).reversed() {
        let source = result.substring(with: match.range)
        if let replacement = mapping[source] { result.replaceCharacters(in: match.range, with: replacement) }
    }
    return result as String
}
