import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Models generated channels, accessors, and factories for a property requirement.
struct PropertyMember {
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

