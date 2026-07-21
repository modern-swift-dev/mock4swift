import Foundation

/// Errors thrown by mock runtime operations.
public enum MockError: Error, Equatable, Sendable {
    case unstubbed(String)
}
