import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Builds support members for a handwritten mock declaration.
struct ManualMockGenerator {
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


private func stripWitnessModifiers(_ text: String) -> String {
    text.replacingOccurrences(
        of: #"\b(?:public|package|internal|fileprivate|private|required)\s+"#,
        with: "",
        options: .regularExpression
    )
}

