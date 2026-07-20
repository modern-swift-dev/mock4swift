import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct Mock4SwiftPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [MockableMacro.self, MockableMembersMacro.self, MockableBodyMacro.self, MockableAccessorMacro.self]
}
