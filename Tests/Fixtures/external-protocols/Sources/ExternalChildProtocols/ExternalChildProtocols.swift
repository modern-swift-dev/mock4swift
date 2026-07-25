import ExternalBaseProtocols

public protocol ExternalIndexedProtocol: ExternalBaseProtocol {
    var enabled: Bool { get set }
    subscript(_ key: String) -> Int { get set }
}

public protocol ExternalNamedProtocol {
    func name() -> String
}

public typealias ExternalProtocolComposition = ExternalIndexedProtocol & ExternalNamedProtocol
