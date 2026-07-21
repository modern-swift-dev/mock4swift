import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Models generated recording and verification for an initializer requirement.
struct InitializerMember {
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

