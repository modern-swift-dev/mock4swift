import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Type-erases generated protocol member models.
enum GeneratedMember {
    case function(FunctionMember)
    case property(PropertyMember)
    case subscriptMember(SubscriptMember)

    var channelName: String { switch self { case .function(let x): x.channelName; case .property(let x): x.channelName; case .subscriptMember(let x): x.channelName } }
    var displayName: String { switch self { case .function(let x): x.displayName; case .property(let x): x.displayName; case .subscriptMember(let x): x.displayName } }
    var argumentsType: String { switch self { case .function(let x): x.argumentsType; case .property(let x): x.argumentsType; case .subscriptMember(let x): x.argumentsType } }
    var outputType: String { switch self { case .function(let x): x.outputType; case .property(let x): x.outputType; case .subscriptMember(let x): x.outputType } }
    var isTransient: Bool { switch self { case .function(let x): x.isTransient; case .property(let x): x.isTransient; case .subscriptMember(let x): x.isTransient } }
    var channelType: String { "\(isTransient ? "TransientMockMember" : "MockMember")<\(argumentsType), \(outputType)>" }
    var channelConstructor: String { "\(channelType)(name: \"\(displayName)\")" }
    var isStatic: Bool { switch self { case .function(let x): x.isStatic; case .property(let x): x.isStatic; case .subscriptMember(let x): x.isStatic } }
    var isGeneric: Bool { switch self { case .function(let x): x.isGeneric; case .property: false; case .subscriptMember(let x): x.isGeneric } }
    var usesRegistry: Bool { switch self { case .function(let x): x.usesRegistry; case .property(let x): x.usesRegistry; case .subscriptMember(let x): x.usesRegistry } }
    var witness: String { switch self { case .function(let x): x.witness; case .property(let x): x.witness; case .subscriptMember(let x): x.witness } }
    var givenFactory: String { switch self { case .function(let x): x.givenFactory; case .property(let x): x.givenFactory; case .subscriptMember(let x): x.givenFactory } }
    var verifyFactory: String { switch self { case .function(let x): x.verifyFactory; case .property(let x): x.verifyFactory; case .subscriptMember(let x): x.verifyFactory } }
    var performFactory: String { switch self { case .function(let x): x.performFactory; case .property(let x): x.performFactory; case .subscriptMember(let x): x.performFactory } }
    var ephemeralChannelDeclaration: String? { if case .function(let value) = self { value.ephemeralChannelDeclaration } else { nil } }
    var ephemeralReset: String? { if case .function(let value) = self, value.hasEphemeralDispatcher, !value.ephemeralUsesRegistry { "        \(value.ephemeralChannelName).reset(scopes)" } else { nil } }
    var argumentsStructDeclaration: String? { switch self { case .function(let value): value.argumentsStructDeclaration; case .subscriptMember(let value): value.argumentsStructDeclaration; case .property: nil } }
}

