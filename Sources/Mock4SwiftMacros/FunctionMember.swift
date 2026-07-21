import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Models generated channels, witnesses, and factories for a function requirement.
struct FunctionMember {
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

