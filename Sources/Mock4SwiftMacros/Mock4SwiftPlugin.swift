import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct Mock4SwiftPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        MockableMacro.self,
        MockableMembersMacro.self,
        MockNoncopyableMacro.self,
        MockableExplicitAccessorMacro.self,
        MockableBodyMacro.self,
        MockableAccessorMacro.self,
    ]
}
