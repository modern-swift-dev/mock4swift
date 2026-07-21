import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

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

