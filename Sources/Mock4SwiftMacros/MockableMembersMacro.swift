import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

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


private func isManualMockMember(_ declaration: DeclSyntax) -> Bool {
    if let function = declaration.as(FunctionDeclSyntax.self) { return function.body == nil }
    if let variable = declaration.as(VariableDeclSyntax.self) { return variable.bindings.first?.accessorBlock == nil }
    if let subscriptDecl = declaration.as(SubscriptDeclSyntax.self) {
        return hasExplicitMockableAccessors(subscriptDecl) || hasExpressionMockableAccessors(subscriptDecl)
    }
    if let initializer = declaration.as(InitializerDeclSyntax.self) { return initializer.body == nil }
    return false
}

