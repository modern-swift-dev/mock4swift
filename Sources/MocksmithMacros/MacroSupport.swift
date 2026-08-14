import Foundation
import SwiftSyntax

private func hasAvailabilityAttribute(_ attributes: AttributeListSyntax) -> Bool {
    attributes.contains { element in
        guard let attribute = element.as(AttributeSyntax.self) else {
            return false
        }
        return attribute.attributeName.trimmedDescription.split(separator: ".").last == "available"
    }
}

func hasAttribute(named expected: String, in attributes: AttributeListSyntax) -> Bool {
    attributes.contains { element in
        guard let attribute = element.as(AttributeSyntax.self) else {
            return false
        }
        return attribute.attributeName.trimmedDescription.split(separator: ".").last == Substring(expected)
    }
}

func availabilityAttributes(_ attributes: AttributeListSyntax) -> String {
    attributes.compactMap { element -> String? in
        guard let attribute = element.as(AttributeSyntax.self),
              attribute.attributeName.trimmedDescription.split(separator: ".").last == "available" else {
            return nil
        }
        return attribute.trimmedDescription
    }.joined(separator: "\n")
}

func witnessAttributePrefix(_ attributes: AttributeListSyntax, indentation: String) -> String {
    let values = attributes.compactMap { element -> String? in
        guard let attribute = element.as(AttributeSyntax.self) else {
            return nil
        }
        let name = attribute.attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? ""
        guard !["available", "MockNoncopyable"].contains(name) else {
            return nil
        }
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
    guard let start = effects.range(of: "throws("), let end = effects[start.upperBound...].firstIndex(of: ")") else {
        return nil
    }
    let type = String(effects[start.upperBound ..< end]).trimmingCharacters(in: .whitespaces)
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

func strippingEscapingAttribute(from type: String) -> String {
    type.replacingOccurrences(of: "@escaping\\s*", with: "", options: .regularExpression)
}

/// Returns whether a type is structurally an optional, without confusing a
/// function that returns an optional or an optional metatype for an optional
/// result itself.
func isOptionalType(_ type: TypeSyntax) -> Bool {
    if type.as(OptionalTypeSyntax.self) != nil {
        return true
    }
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return isOptionalType(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
       let element = tuple.elements.first {
        return isOptionalType(element.type)
    }
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return identifier.name.text == "Optional"
    }
    if let member = type.as(MemberTypeSyntax.self),
       member.name.text == "Optional",
       let base = member.baseType.as(IdentifierTypeSyntax.self) {
        return base.name.text == "Swift"
    }
    return false
}

func isVoidType(_ type: TypeSyntax) -> Bool {
    if let attributed = type.as(AttributedTypeSyntax.self) {
        return isVoidType(attributed.baseType)
    }
    if let tuple = type.as(TupleTypeSyntax.self) {
        if tuple.elements.isEmpty {
            return true
        }
        if tuple.elements.count == 1, let element = tuple.elements.first {
            return isVoidType(element.type)
        }
        return false
    }
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        return identifier.name.text == "Void"
    }
    if let member = type.as(MemberTypeSyntax.self),
       member.name.text == "Void",
       let base = member.baseType.as(IdentifierTypeSyntax.self) {
        return base.name.text == "Swift"
    }
    return false
}

func opaqueParameterType(_ text: String, position: Int) -> (name: String, constraint: String)? {
    var type = text
    for prefix in ["inout ", "borrowing ", "consuming ", "sending "] where type.hasPrefix(prefix) {
        type.removeFirst(prefix.count)
    }
    guard type.hasPrefix("some ") else {
        return nil
    }
    return ("_MockOpaque\(position)", String(type.dropFirst(5)))
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
          let expression = try? NSRegularExpression(pattern: "\\b(?:\(names.joined(separator: "|")))\\b") else {
        return text
    }
    let result = NSMutableString(string: text)
    let range = NSRange(location: 0, length: result.length)
    for match in expression.matches(in: text, range: range).reversed() {
        let source = result.substring(with: match.range)
        if let replacement = mapping[source] {
            result.replaceCharacters(in: match.range, with: replacement)
        }
    }
    return result as String
}

extension String {
    mutating func replaceFirst(_ target: String, with replacement: String) {
        guard let range = range(of: target) else {
            return
        }
        replaceSubrange(range, with: replacement)
    }
}
