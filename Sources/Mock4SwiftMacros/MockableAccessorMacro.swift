import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Synthesizes accessors for handwritten mock properties and subscripts.
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

