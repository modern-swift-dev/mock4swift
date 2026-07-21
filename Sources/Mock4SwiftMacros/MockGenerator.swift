import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Validates a protocol and renders its generated mock implementation.
struct MockGenerator {
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

