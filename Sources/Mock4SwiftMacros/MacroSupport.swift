import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

func hasExplicitMockableAccessors(_ declaration: SubscriptDeclSyntax) -> Bool {
    guard let block = declaration.accessorBlock, case .accessors(let accessors) = block.accessors else { return false }
    return !accessors.isEmpty && accessors.allSatisfy { accessor in
        accessor.attributes.contains { element in
            guard let attribute = element.as(AttributeSyntax.self) else { return false }
            return attribute.attributeName.trimmedDescription.split(separator: ".").last == "MockableAccessor"
        }
    }
}

func hasExpressionMockableAccessors(_ declaration: SubscriptDeclSyntax) -> Bool {
    guard let block = declaration.accessorBlock, case .accessors(let accessors) = block.accessors else { return false }
    return !accessors.isEmpty && accessors.allSatisfy { $0.body?.trimmedDescription.contains("#MockableAccessor") == true }
}


func witnessIndex(_ node: AttributeSyntax) -> Int? {
    guard case .argumentList(let arguments) = node.arguments,
          let literal = arguments.first?.expression.as(IntegerLiteralExprSyntax.self) else { return nil }
    return Int(literal.literal.text)
}


func enclosingMockInfo(_ context: some MacroExpansionContext) -> (name: String, isActor: Bool, isolated: String)? {
    for syntax in context.lexicalContext.reversed() {
        if let declaration = syntax.as(ClassDeclSyntax.self) {
            let isolated = declaration.attributes.contains { element in
                guard let attribute = element.as(AttributeSyntax.self) else { return false }
                let name = attribute.attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
                return name.hasSuffix("Actor") && name != "MockableMembers"
            }
            return (declaration.name.text, false, isolated ? "nonisolated " : "")
        }
        if let declaration = syntax.as(ActorDeclSyntax.self) {
            return (declaration.name.text, true, "nonisolated ")
        }
    }
    return nil
}


private func hasAvailabilityAttribute(_ attributes: AttributeListSyntax) -> Bool {
    attributes.contains { element in
        guard let attribute = element.as(AttributeSyntax.self) else { return false }
        return attribute.attributeName.trimmedDescription.split(separator: ".").last == "available"
    }
}

func hasAttribute(named expected: String, in attributes: AttributeListSyntax) -> Bool {
    attributes.contains { element in
        guard let attribute = element.as(AttributeSyntax.self) else { return false }
        return attribute.attributeName.trimmedDescription.split(separator: ".").last == Substring(expected)
    }
}

func availabilityAttributes(_ attributes: AttributeListSyntax) -> String {
    attributes.compactMap { element -> String? in
        guard let attribute = element.as(AttributeSyntax.self),
              attribute.attributeName.trimmedDescription.split(separator: ".").last == "available" else { return nil }
        return attribute.trimmedDescription
    }.joined(separator: "\n")
}

func witnessAttributePrefix(_ attributes: AttributeListSyntax, indentation: String) -> String {
    let values = attributes.compactMap { element -> String? in
        guard let attribute = element.as(AttributeSyntax.self) else { return nil }
        let name = attribute.attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
        guard !["available", "MockNoncopyable", "MockableAccessor"].contains(name) else { return nil }
        return indentation + attribute.trimmedDescription
    }
    return values.isEmpty ? "" : values.joined(separator: "\n") + "\n"
}

func accessorHeader(_ accessor: AccessorDeclSyntax) -> String {
    var copy = accessor
    copy.body = nil
    copy.attributes = []
    return copy.trimmedDescription
}

func parsedTypedError(_ effects: String) -> String? {
    guard let start = effects.range(of: "throws("), let end = effects[start.upperBound...].firstIndex(of: ")") else { return nil }
    let type = String(effects[start.upperBound..<end]).trimmingCharacters(in: .whitespaces)
    return ["Error", "any Error", "any Swift.Error"].contains(type) ? nil : type
}

func stableIdentifier(_ text: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(hash, radix: 16)
}

func objectIdentifierList(_ metatypes: String) -> String {
    let values = metatypes.split(separator: ",").map { "ObjectIdentifier(\($0.trimmingCharacters(in: .whitespaces)))" }
    return "[\(values.joined(separator: ", "))]"
}


func rewriteType(_ text: String, replacements: [String: String], mockType: String) -> String {
    var text = text
    for (associated, replacement) in replacements {
        text = text.replacingOccurrences(
            of: #"\bSelf\s*\.\s*"# + NSRegularExpression.escapedPattern(for: associated) + #"\b"#,
            with: replacement,
            options: .regularExpression
        )
    }
    let mapping = replacements.merging(["Self": mockType]) { current, _ in current }
    let names = mapping.keys.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern)
    guard !names.isEmpty,
          let expression = try? NSRegularExpression(pattern: "\\b(?:\(names.joined(separator: "|")))\\b") else { return text }
    let result = NSMutableString(string: text)
    let range = NSRange(location: 0, length: result.length)
    for match in expression.matches(in: text, range: range).reversed() {
        let source = result.substring(with: match.range)
        if let replacement = mapping[source] { result.replaceCharacters(in: match.range, with: replacement) }
    }
    return result as String
}
