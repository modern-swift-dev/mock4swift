import Foundation

/// Reports whether mock verification succeeded and describes the result.
public struct VerificationResult: Sendable, Equatable, CustomStringConvertible {
    public let success: Bool
    public let message: String

    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }

    public var description: String {
        message
    }
}

public func _mocksmithNoMoreInteractionsResult(
    _ invocations: [_MocksmithInvocation]
) -> VerificationResult {
    let invocations = invocations.sorted { $0.sequence < $1.sequence }
    guard !invocations.isEmpty else {
        return .init(success: true, message: "No unverified interactions")
    }

    var counts: [String: Int] = [:]
    var members: [String] = []
    for invocation in invocations {
        let member = invocation.member.replacingOccurrences(of: "_:", with: "*:")
        if counts[member] == nil {
            members.append(member)
        }
        counts[member, default: 0] += 1
    }
    let summary = members.map { "\($0) ×\(counts[$0, default: 0])" }.joined(separator: ", ")
    return .init(success: false, message: "Unverified interactions: \(summary)")
}
