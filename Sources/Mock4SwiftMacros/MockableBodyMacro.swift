import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Synthesizes bodies for handwritten mock methods and initializers.
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

