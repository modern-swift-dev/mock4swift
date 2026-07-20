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
        let markers = Set(["AnyObject", "Sendable", "Actor"])
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
        guard member.is(FunctionDeclSyntax.self) || member.is(VariableDeclSyntax.self)
                || member.is(SubscriptDeclSyntax.self) || member.is(InitializerDeclSyntax.self),
              let index = declaration.memberBlock.members.enumerated().first(where: { $0.element.decl.trimmedDescription == member.trimmedDescription })?.offset else { return [] }
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
            let member = InitializerMember(declaration: initializer, index: index, access: "", replacements: [:], mockType: info.name, factoryIsolation: info.isolated, isActor: info.isActor)
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
            if let subscriptDecl = item.decl.as(SubscriptDeclSyntax.self), subscriptDecl.accessorBlock == nil {
                return stripWitnessModifiers(subscriptDecl.trimmedDescription) + " { get }"
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
            if item.decl.trimmedDescription.range(of: #"\bSelf\s*\."#, options: .regularExpression) != nil {
                diagnose("dependent Self member types are not supported yet", at: item.decl, in: context)
                valid = false
                continue
            }
            if let function = item.decl.as(FunctionDeclSyntax.self) {
                let isRethrows = (function.signature.effectSpecifiers?.trimmedDescription ?? "").contains("rethrows")
                if hasAvailabilityAttribute(function.attributes) {
                    diagnose("member-level availability is not supported yet; apply @available to the protocol", at: function, in: context)
                    valid = false
                } else if function.genericParameterClause?.parameters.contains(where: { $0.specifier != nil }) == true {
                    diagnose("generic parameter packs are not supported yet", at: function, in: context)
                    valid = false
                } else if function.trimmedDescription.contains("~Copyable") || function.trimmedDescription.contains("some ") {
                    diagnose("noncopyable and opaque requirements are not supported yet", at: function, in: context)
                    valid = false
                } else if !isRethrows && function.signature.parameterClause.parameters.contains(where: {
                    $0.type.trimmedDescription.contains("->") && !$0.trimmedDescription.contains("@escaping")
                }) {
                    diagnose("nonescaping function parameters cannot be recorded; mark the parameter @escaping", at: function, in: context)
                    valid = false
                }
                continue
            }
            if let initializer = item.decl.as(InitializerDeclSyntax.self) {
                if hasAvailabilityAttribute(initializer.attributes) {
                    diagnose("member-level availability is not supported yet; apply @available to the protocol", at: initializer, in: context)
                    valid = false
                } else if initializer.genericParameterClause != nil {
                    diagnose("generic initializer requirements are not supported yet", at: initializer, in: context)
                    valid = false
                } else if initializer.trimmedDescription.contains("~Copyable") {
                    diagnose("noncopyable initializer parameters are not supported yet", at: initializer, in: context)
                    valid = false
                } else if initializer.signature.parameterClause.parameters.contains(where: {
                    $0.type.trimmedDescription.contains("->") && !$0.trimmedDescription.contains("@escaping")
                }) {
                    diagnose("nonescaping initializer closures cannot be recorded", at: initializer, in: context)
                    valid = false
                }
                continue
            }
            if let variable = item.decl.as(VariableDeclSyntax.self) {
                let accessors = variable.bindings.first?.accessorBlock?.trimmedDescription ?? ""
                if hasAvailabilityAttribute(variable.attributes) {
                    diagnose("member-level availability is not supported yet; apply @available to the protocol", at: variable, in: context)
                    valid = false
                    continue
                } else if accessors.range(of: #"\b(async|throws)\b"#, options: .regularExpression) != nil {
                    diagnose("async and throwing property accessors are not supported yet", at: variable, in: context)
                    valid = false
                    continue
                } else if PropertyMember.isSupported(variable) {
                    continue
                }
            }
            if let subscriptDecl = item.decl.as(SubscriptDeclSyntax.self) {
                if hasAvailabilityAttribute(subscriptDecl.attributes) {
                    diagnose("member-level availability is not supported yet; apply @available to the protocol", at: subscriptDecl, in: context)
                    valid = false
                    continue
                } else if subscriptDecl.modifiers.contains(where: { ["static", "class"].contains($0.name.text) }) {
                    diagnose("static subscript requirements are not supported yet", at: subscriptDecl, in: context)
                    valid = false
                    continue
                } else if subscriptDecl.genericParameterClause != nil {
                    diagnose("generic subscript requirements are not supported yet", at: subscriptDecl, in: context)
                    valid = false
                    continue
                } else if subscriptDecl.trimmedDescription.range(of: #"\b(async|throws)\b"#, options: .regularExpression) != nil {
                    diagnose("async and throwing subscript accessors are not supported yet", at: subscriptDecl, in: context)
                    valid = false
                    continue
                } else if SubscriptMember.isSupported(subscriptDecl) {
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
                InitializerMember(declaration: $0, index: index, access: access, replacements: replacements, mockType: mockType, factoryIsolation: configurationIsolation, isActor: isActor)
            }
        }
        let instance = all.filter { !$0.isStatic }
        let staticMembers = all.filter(\.isStatic)
        let genericMembers = instance.filter(\.isGeneric)
        let memberChannels = all.filter { !$0.isGeneric }.map { member in
            if member.isStatic {
                return "    \(isolation)private static var \(member.channelName): MockMember<\(member.argumentsType), \(member.outputType)> {\n        StaticMockRegistry.shared.member(owner: Self.self, key: \"\(member.channelName)\") { MockMember(name: \"\(member.displayName)\") }\n    }"
            }
            return "    \(isolation)private let \(member.channelName) = MockMember<\(member.argumentsType), \(member.outputType)>(name: \"\(member.displayName)\")"
        }
        let initializerChannels = initializers.map { "    \(isolation)private let \($0.channelName) = MockMember<\($0.argumentsType), Void>(name: \"\($0.displayName)\")" }
        let channels = (memberChannels + initializerChannels).joined(separator: "\n")
        let initializerWitnesses = initializers.map(\.witness).joined(separator: "\n\n")
        let memberWitnesses = all.map(\.witness).filter { !$0.isEmpty }
        let witnesses = (memberWitnesses + (initializerWitnesses.isEmpty ? [] : [initializerWitnesses])).joined(separator: "\n\n")
        let givenFactories = instance.map(\.givenFactory).joined(separator: "\n\n")
        let verifyFactories = (instance.map(\.verifyFactory) + initializers.map(\.verifyFactory)).joined(separator: "\n\n")
        let performFactories = instance.map(\.performFactory).joined(separator: "\n\n")
        let staticGivenFactories = staticMembers.map(\.givenFactory).joined(separator: "\n\n")
        let staticVerifyFactories = staticMembers.map(\.verifyFactory).joined(separator: "\n\n")
        let staticPerformFactories = staticMembers.map(\.performFactory).joined(separator: "\n\n")
        let resets = (instance.filter { !$0.isGeneric }.map { "        \($0.channelName).reset(scopes)" } + initializers.map { "        \($0.channelName).reset(scopes)" }).joined(separator: "\n")
        let channelSection = channels.isEmpty ? "" : channels + "\n\n"
        let givenSection = givenFactories.isEmpty ? "" : "\n\n" + givenFactories
        let verifySection = verifyFactories.isEmpty ? "" : "\n\n" + verifyFactories
        let performSection = performFactories.isEmpty ? "" : "\n\n" + performFactories
        let witnessSection = witnesses.isEmpty ? "" : "\n\n" + witnesses
        let resetSection = resets.isEmpty ? "" : "\n" + resets + "\n    "
        let genericRegistry = genericMembers.isEmpty ? "" : "    \(isolation)private let _genericMockRegistry = GenericMockRegistry()\n\n"
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

        return attributePrefix + access + "final \(kind) \(name)Mock\(generics): \(name), Mock\(staticConformance)\(mockWhere) {\n"
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
            + "    \(access)\(isolation)func resetMock(_ scopes: MockScope...) {\(resetSection)\(genericMembers.isEmpty ? "" : "\n        _genericMockRegistry.reset(scopes)")\n    }"
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
    var isStatic: Bool { switch self { case .function(let x): x.isStatic; case .property(let x): x.isStatic; case .subscriptMember: false } }
    var isGeneric: Bool { switch self { case .function(let x): x.isGeneric; case .property, .subscriptMember: false } }
    var witness: String { switch self { case .function(let x): x.witness; case .property(let x): x.witness; case .subscriptMember(let x): x.witness } }
    var givenFactory: String { switch self { case .function(let x): x.givenFactory; case .property(let x): x.givenFactory; case .subscriptMember(let x): x.givenFactory } }
    var verifyFactory: String { switch self { case .function(let x): x.verifyFactory; case .property(let x): x.verifyFactory; case .subscriptMember(let x): x.verifyFactory } }
    var performFactory: String { switch self { case .function(let x): x.performFactory; case .property(let x): x.performFactory; case .subscriptMember(let x): x.performFactory } }
}

private struct ParameterInfo {
    let external: String
    let local: String
    let type: String
    let matcher: String
    let position: Int

    var declaration: String { "\(external == "_" ? "_" : external) \(matcher): Parameter<\(type)>" }
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
            if isRethrows && parameter.type.trimmedDescription.contains("->") && !parameter.trimmedDescription.contains("@escaping") {
                return nil
            }
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
        switch parameters.count {
        case 0: "Void"
        case 1: parameters[0].type
        default: "(" + parameters.map { "\($0.local): \($0.type)" }.joined(separator: ", ") + ")"
        }
    }
    var argumentsExpression: String {
        switch parameters.count {
        case 0: "()"
        case 1: parameters[0].local
        default: "(" + parameters.map { "\($0.local): \($0.local)" }.joined(separator: ", ") + ")"
        }
    }
    var outputType: String { declaration.signature.returnClause.map { rewriteType($0.type.trimmedDescription, replacements: replacements, mockType: mockType) } ?? "Void" }
    var isStatic: Bool { declaration.modifiers.contains { ["static", "class"].contains($0.name.text) } }
    var isGeneric: Bool { declaration.genericParameterClause != nil }
    var isRethrows: Bool { (declaration.signature.effectSpecifiers?.trimmedDescription ?? "").contains("rethrows") }
    var isThrowing: Bool { (declaration.signature.effectSpecifiers?.trimmedDescription ?? "").contains("throws") }
    var genericClause: String { declaration.genericParameterClause?.trimmedDescription ?? "" }
    var whereClause: String { declaration.genericWhereClause.map { " " + rewriteType($0.trimmedDescription, replacements: replacements, mockType: mockType) } ?? "" }
    var genericTypes: String {
        declaration.genericParameterClause?.parameters.map { "\($0.name.text).self" }.joined(separator: ", ") ?? ""
    }
    var registryResolution: String {
        guard isGeneric else { return "" }
        if isStatic {
            return "let member: MockMember<\(argumentsType), \(outputType)> = StaticMockRegistry.shared.member(owner: mock, key: \"\(channelName)\", types: [\(genericTypes)]) { MockMember(name: \"\(displayName)\") }\n            "
        }
        return "let member: MockMember<\(argumentsType), \(outputType)> = mock._genericMockRegistry.member(key: \"\(channelName)\", types: [\(genericTypes)]) { MockMember(name: \"\(displayName)\") }\n            "
    }
    var witnessRegistryResolution: String {
        guard isGeneric else { return "" }
        if isStatic {
            return "let member: MockMember<\(argumentsType), \(outputType)> = StaticMockRegistry.shared.member(owner: Self.self, key: \"\(channelName)\", types: [\(genericTypes)]) { MockMember(name: \"\(displayName)\") }\n        "
        }
        return "let member: MockMember<\(argumentsType), \(outputType)> = _genericMockRegistry.member(key: \"\(channelName)\", types: [\(genericTypes)]) { MockMember(name: \"\(displayName)\") }\n        "
    }
    var channelReference: String { isGeneric ? "member" : "mock.\(channelName)" }
    var typedError: String? {
        let effects = declaration.signature.effectSpecifiers?.trimmedDescription ?? ""
        guard let start = effects.range(of: "throws("), let end = effects[start.upperBound...].firstIndex(of: ")") else { return nil }
        let type = String(effects[start.upperBound..<end]).trimmingCharacters(in: .whitespaces)
        return ["Error", "any Error", "any Swift.Error"].contains(type) ? nil : type
    }
    var matcherDeclarations: String { parameters.map(\.declaration).joined(separator: ", ") }
    var matcherClosure: String {
        guard !parameters.isEmpty else { return "{ _ in true }" }
        return "{ arguments in " + parameters.map { parameter in
            let access = parameters.count == 1 ? "arguments" : "arguments.\(parameter.local)"
            return "\(parameter.matcher).matches(\(access))"
        }.joined(separator: " && ") + " }"
    }
    var specificity: String { parameters.isEmpty ? "0" : parameters.map { "\($0.matcher).specificity" }.joined(separator: " + ") }
    var actionType: String {
        switch parameters.count {
        case 0: "() -> Void"
        case 1: "(\(parameters[0].type)) -> Void"
        default: "(" + parameters.map(\.type).joined(separator: ", ") + ") -> Void"
        }
    }
    var actionCall: String {
        switch parameters.count {
        case 0: "action()"
        case 1: "action(arguments)"
        default: "action(" + parameters.map { "arguments.\($0.local)" }.joined(separator: ", ") + ")"
        }
    }
    var signaturePrefix: String {
        let modifiers = declaration.modifiers.compactMap { modifier -> String? in
            if ["mutating", "nonmutating"].contains(modifier.name.text) { return nil }
            return modifier.name.text == "class" ? "static" : modifier.trimmedDescription
        }.joined(separator: " ")
        return (access + (modifiers.isEmpty ? "" : modifiers + " "))
    }
    var witness: String {
        let signatureText = rewriteType(declaration.signature.trimmedDescription, replacements: replacements, mockType: mockType)
        let signature = "\(signaturePrefix)func \(declaration.name.trimmedDescription)\(genericClause)\(signatureText)\(whereClause)"
        let invocation = "\(isGeneric ? "member" : channelName).invoke(\(argumentsExpression))"
        if let typedError {
            return """
                \(signature) {
                    \(witnessRegistryResolution)\
                    do { return try \(invocation) }
                    catch let error as \(typedError) { throw error }
                    catch { preconditionFailure("Invalid or unstubbed typed-throws member \(displayName): \\(error)") }
                }
            """.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n")
        }
        if isRethrows {
            return """
                \(signature) {
                    \(witnessRegistryResolution)\
                    do { return try \(invocation) }
                    catch { preconditionFailure("Invalid or unstubbed rethrows member \(displayName): \\(error)") }
                }
            """.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n")
        }
        if isThrowing { return "    \(signature) {\n        \(witnessRegistryResolution)try \(invocation)\n    }" }
        return """
            \(signature) {
                \(witnessRegistryResolution)do { return try \(invocation) }
                catch { preconditionFailure("Unstubbed nonthrowing member \(displayName): \\(error)") }
            }
        """.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }.joined(separator: "\n")
    }
    var givenFactory: String {
        let leading = matcherDeclarations.isEmpty ? "" : matcherDeclarations + ", "
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
        factory(factorySignature(arguments: matcherDeclarations), body: "\(registryResolution)return \(channelReference).verification(matching: \(matcherClosure), count: count)", verify: true)
    }
    var performFactory: String {
        let leading = matcherDeclarations.isEmpty ? "" : matcherDeclarations + ", "
        let outcomes = outputType == "Void" ? ", outcomes: [.returnValue(())]" : ""
        let body = "\(registryResolution)\(channelReference).addAction(matching: \(matcherClosure), specificity: \(specificity)\(outcomes)) { arguments in \(actionCall) }"
        return factory(factorySignature(arguments: "\(leading)_ action: @escaping \(actionType)"), body: body)
    }

    private func factorySignature(arguments: String) -> String {
        let genericParameters = declaration.genericParameterClause?.parameters.map(\.name.text) ?? []
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
        let closure = verify ? "Self { mock, count in\n            \(body)\n        }" : "Self { mock in\n            \(body)\n        }"
        return """
                \(access)\(signature) {
                    \(closure)
                }
        """
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
    let factoryIsolation: String

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
        let type = rewriteType(annotation.type.trimmedDescription, replacements: replacements, mockType: mockType)
        var result = [Self(name: pattern.identifier.text, type: type, kind: .get, index: index, access: access, isReadWrite: settable, isStatic: isStatic, factoryIsolation: factoryIsolation)]
        if settable { result.append(Self(name: pattern.identifier.text, type: type, kind: .set, index: index, access: access, isReadWrite: true, isStatic: isStatic, factoryIsolation: factoryIsolation)) }
        return result
    }

    var suffix: String { kind == .get ? "get" : "set" }
    var channelName: String { "_mock_\(name)_\(suffix)_\(index)" }
    var displayName: String { "\(name).\(suffix)" }
    var argumentsType: String { kind == .get ? "Void" : type }
    var outputType: String { kind == .get ? type : "Void" }
    var witness: String {
        guard kind == .get else { return "" }
        let getter = "get {\n            do { return try _mock_\(name)_get_\(index).invoke(()) }\n            catch { preconditionFailure(\"Unstubbed nonthrowing member \(name).get: \\(error)\") }\n        }"
        let setter = isReadWrite ? "\n        set {\n            do { return try _mock_\(name)_set_\(index).invoke(newValue) }\n            catch { preconditionFailure(\"Unstubbed nonthrowing member \(name).set: \\(error)\") }\n        }" : ""
        return "    \(access)\(isStatic ? "static " : "")var \(name): \(type) {\n        \(getter)\(setter)\n    }"
    }
    var givenFactory: String {
        switch kind {
        case .get:
            return factory("static func \(name)(willReturn values: \(type)...) -> Self", "mock.\(channelName).addStub(matching: { _ in true }, specificity: 0, outcomes: values.map(StubOutcome.returnValue))")
        case .set:
            return factory("static func \(name)(set matching: Parameter<\(type)>) -> Self", "mock.\(channelName).addStub(matching: { matching.matches($0) }, specificity: matching.specificity, outcomes: [.returnValue(())])")
        }
    }
    var verifyFactory: String {
        switch kind {
        case .get:
            return verifyFactory("static func \(name)() -> Self", "mock.\(channelName).verification(matching: { _ in true }, count: count)")
        case .set:
            return verifyFactory("static func \(name)(set matching: Parameter<\(type)>) -> Self", "mock.\(channelName).verification(matching: { matching.matches($0) }, count: count)")
        }
    }
    var performFactory: String {
        switch kind {
        case .get:
            return factory("static func \(name)(_ action: @escaping () -> Void) -> Self", "mock.\(channelName).addAction(matching: { _ in true }, specificity: 0) { _ in action() }")
        case .set:
            return factory("static func \(name)(set matching: Parameter<\(type)>, _ action: @escaping (\(type)) -> Void) -> Self", "mock.\(channelName).addAction(matching: { matching.matches($0) }, specificity: matching.specificity, outcomes: [.returnValue(())], action: action)")
        }
    }

    private func factory(_ signature: String, _ body: String) -> String {
        "        \(access)\(factoryIsolation)\(signature) {\n            Self { mock in\n                \(body)\n            }\n        }"
    }
    private func verifyFactory(_ signature: String, _ body: String) -> String {
        "        \(access)\(factoryIsolation)\(signature) {\n            Self { mock, count in\n                \(body)\n            }\n        }"
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

    static func isSupported(_ declaration: SubscriptDeclSyntax) -> Bool {
        !declaration.modifiers.contains { ["static", "class"].contains($0.name.text) }
            && declaration.genericParameterClause == nil
            && !declaration.trimmedDescription.contains(" async")
            && !declaration.trimmedDescription.contains(" throws")
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
        var result = [Self(declaration: declaration, kind: .get, index: index, access: access, parameters: parameters, valueType: valueType, isReadWrite: settable, factoryIsolation: factoryIsolation, replacements: replacements, mockType: mockType)]
        if settable { result.append(Self(declaration: declaration, kind: .set, index: index, access: access, parameters: parameters, valueType: valueType, isReadWrite: true, factoryIsolation: factoryIsolation, replacements: replacements, mockType: mockType)) }
        return result
    }

    var channelName: String { "_mock_subscript_\(kind == .get ? "get" : "set")_\(index)" }
    var displayName: String { "subscript.\(kind == .get ? "get" : "set")" }
    var argumentsType: String {
        let fields = parameters.map { "\($0.local): \($0.type)" } + (kind == .set ? ["newValue: \(valueType)"] : [])
        if fields.isEmpty { return "Void" }
        if fields.count == 1 { return parameters[0].type }
        return "(" + fields.joined(separator: ", ") + ")"
    }
    var outputType: String { kind == .get ? valueType : "Void" }
    var isStatic: Bool { false }
    var matcherDeclarations: String {
        let base = parameters.map(\.declaration)
        return (base + (kind == .set ? ["value: Parameter<\(valueType)>"] : [])).joined(separator: ", ")
    }
    var specificity: String {
        let parts = parameters.map { "\($0.matcher).specificity" } + (kind == .set ? ["value.specificity"] : [])
        return parts.isEmpty ? "0" : parts.joined(separator: " + ")
    }
    var matcherClosure: String {
        var parts = parameters.enumerated().map { position, parameter in
            let argument = argumentsFieldCount == 1 ? "arguments" : "arguments.\(parameter.local)"
            return "\(parameter.matcher).matches(\(argument))"
        }
        if kind == .set { parts.append("value.matches(arguments.newValue)") }
        return parts.isEmpty ? "{ _ in true }" : "{ arguments in " + parts.joined(separator: " && ") + " }"
    }
    var argumentsFieldCount: Int { parameters.count + (kind == .set ? 1 : 0) }
    var invocationArguments: String {
        let fields = parameters.map { "\($0.local): \($0.local)" } + (kind == .set ? ["newValue: newValue"] : [])
        if fields.isEmpty { return "()" }
        if fields.count == 1 { return parameters[0].local }
        return "(" + fields.joined(separator: ", ") + ")"
    }
    var witness: String {
        guard kind == .get else { return "" }
        let generics = declaration.genericParameterClause?.trimmedDescription ?? ""
        let whereClause = declaration.genericWhereClause.map { rewriteType($0.trimmedDescription, replacements: replacements, mockType: mockType) } ?? ""
        let getter = "get {\n            do { return try _mock_subscript_get_\(index).invoke(\(invocationArguments)) }\n            catch { preconditionFailure(\"Unstubbed nonthrowing member subscript.get: \\(error)\") }\n        }"
        let setterArgs = Self(declaration: declaration, kind: .set, index: index, access: access, parameters: parameters, valueType: valueType, isReadWrite: true, factoryIsolation: factoryIsolation, replacements: replacements, mockType: mockType).invocationArguments
        let setter = isReadWrite ? "\n        set {\n            do { return try _mock_subscript_set_\(index).invoke(\(setterArgs)) }\n            catch { preconditionFailure(\"Unstubbed nonthrowing member subscript.set: \\(error)\") }\n        }" : ""
        let parameterClause = rewriteType(declaration.parameterClause.trimmedDescription, replacements: replacements, mockType: mockType)
        return "    \(access)subscript\(generics)\(parameterClause) -> \(valueType) \(whereClause){\n        \(getter)\(setter)\n    }"
    }
    var givenFactory: String {
        switch kind {
        case .get:
            let leading = matcherDeclarations.isEmpty ? "" : matcherDeclarations + ", "
            return factory("static func subscriptGet(\(leading)willReturn values: \(valueType)...) -> Self", "mock.\(channelName).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: values.map(StubOutcome.returnValue))")
        case .set:
            return factory("static func subscriptSet(\(matcherDeclarations)) -> Self", "mock.\(channelName).addStub(matching: \(matcherClosure), specificity: \(specificity), outcomes: [.returnValue(())])")
        }
    }
    var verifyFactory: String {
        verifyFactory("static func \(kind == .get ? "subscriptGet" : "subscriptSet")(\(matcherDeclarations)) -> Self", "mock.\(channelName).verification(matching: \(matcherClosure), count: count)")
    }
    var performFactory: String {
        let actionTypes = parameters.map(\.type) + (kind == .set ? [valueType] : [])
        let actionType = "(" + actionTypes.joined(separator: ", ") + ") -> Void"
        let actionArgs = parameters.map { argumentsFieldCount == 1 ? "arguments" : "arguments.\($0.local)" } + (kind == .set ? ["arguments.newValue"] : [])
        let leading = matcherDeclarations.isEmpty ? "" : matcherDeclarations + ", "
        let outcomes = kind == .set ? ", outcomes: [.returnValue(())]" : ""
        let body = "mock.\(channelName).addAction(matching: \(matcherClosure), specificity: \(specificity)\(outcomes)) { arguments in action(\(actionArgs.joined(separator: ", "))) }"
        return factory("static func \(kind == .get ? "subscriptGet" : "subscriptSet")(\(leading)_ action: @escaping \(actionType)) -> Self", body)
    }

    private func factory(_ signature: String, _ body: String) -> String {
        "        \(access)\(factoryIsolation)\(signature) {\n            Self { mock in\n                \(body)\n            }\n        }"
    }
    private func verifyFactory(_ signature: String, _ body: String) -> String {
        "        \(access)\(factoryIsolation)\(signature) {\n            Self { mock, count in\n                \(body)\n            }\n        }"
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
        switch parameters.count {
        case 0: "Void"
        case 1: parameters[0].type
        default: "(" + parameters.map { "\($0.local): \($0.type)" }.joined(separator: ", ") + ")"
        }
    }
    var argumentsExpression: String {
        switch parameters.count {
        case 0: "()"
        case 1: parameters[0].local
        default: "(" + parameters.map { "\($0.local): \($0.local)" }.joined(separator: ", ") + ")"
        }
    }
    var matcherDeclarations: String { parameters.map(\.declaration).joined(separator: ", ") }
    var matcherClosure: String {
        guard !parameters.isEmpty else { return "{ _ in true }" }
        return "{ arguments in " + parameters.map { parameter in
            let value = parameters.count == 1 ? "arguments" : "arguments.\(parameter.local)"
            return "\(parameter.matcher).matches(\(value))"
        }.joined(separator: " && ") + " }"
    }
    var witness: String {
        let required = isActor ? "" : "required "
        let genericClause = declaration.genericParameterClause?.trimmedDescription ?? ""
        let signature = rewriteType(declaration.signature.trimmedDescription, replacements: replacements, mockType: mockType)
        let whereClause = declaration.genericWhereClause.map { " " + rewriteType($0.trimmedDescription, replacements: replacements, mockType: mockType) } ?? ""
        let attributes = declaration.attributes.map(\.trimmedDescription).joined(separator: "\n    ")
        let attributePrefix = attributes.isEmpty ? "" : "    " + attributes + "\n"
        let ignored = Set(["required", "public", "package", "internal", "fileprivate", "private"])
        let modifiers = declaration.modifiers.map(\.name.text).filter { !ignored.contains($0) }.joined(separator: " ")
        let modifierPrefix = modifiers.isEmpty ? "" : modifiers + " "
        return "\(attributePrefix)    \(access)\(required)\(modifierPrefix)init\(declaration.optionalMark?.text ?? "")\(genericClause)\(signature)\(whereClause) {\n        \(channelName).record(\(argumentsExpression))\n    }"
    }
    var verifyFactory: String {
        """
                \(access)\(factoryIsolation)static func initializer(\(matcherDeclarations)) -> Self {
                    Self { mock, count in
                        mock.\(channelName).verification(matching: \(matcherClosure), count: count)
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

private func diagnose(
    _ message: String,
    at node: some SyntaxProtocol,
    in context: some MacroExpansionContext
) {
    context.diagnose(Diagnostic(node: Syntax(node), message: MacroDiagnostic(message: message)))
}

private func rewriteType(_ text: String, replacements: [String: String], mockType: String) -> String {
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
