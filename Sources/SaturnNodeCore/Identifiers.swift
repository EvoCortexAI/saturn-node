import Foundation

public struct SaturnNodeIdentifier: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    private static func isValid(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 128 else { return false }
        guard let first = value.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first) else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._:-"))
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

public typealias WorkloadIdentifier = SaturnNodeIdentifier
public typealias DeploymentIdentifier = SaturnNodeIdentifier
public typealias ModelIdentifier = SaturnNodeIdentifier
public typealias CredentialIdentifier = SaturnNodeIdentifier
public typealias RequestIdentifier = SaturnNodeIdentifier
