import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// Registers Mocksmith macro implementations with the Swift compiler.
@main struct MocksmithPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MockableMacro.self,
        ResolvedMockableMacro.self,
        MockNoncopyableMacro.self
    ]
}
