import Foundation

/// Reports whether mock verification succeeded and describes the result.
public struct VerificationResult: Sendable, Equatable, CustomStringConvertible {
    public let success: Bool
    public let message: String

    public init(success: Bool, message: String) {
        self.success = success
        self.message = message
    }

    public var description: String { message }
}
