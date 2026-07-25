import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Reports validation failures produced by Mock4Swift macros.
private struct MacroDiagnostic: DiagnosticMessage {
    let message: String
    var diagnosticID: MessageID {
        MessageID(domain: "Mock4Swift.Mockable", id: message)
    }

    var severity: DiagnosticSeverity {
        .error
    }
}

func diagnose(
    _ message: String,
    at node: some SyntaxProtocol,
    in context: some MacroExpansionContext
) {
    context.diagnose(Diagnostic(node: Syntax(node), message: MacroDiagnostic(message: message)))
}
