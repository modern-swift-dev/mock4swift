import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// Registers Mock4Swift macro implementations with the Swift compiler.
@main
struct Mock4SwiftPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MockableMacro.self,
        ResolvedMockableMacro.self,
        MockNoncopyableMacro.self,
    ]
}
