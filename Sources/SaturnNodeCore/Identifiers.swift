import Foundation

public struct SaturnNodeIdentifier: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard Self.isValid(rawValue) else { return nil }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Identifier does not satisfy the Saturn contract."
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

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

public struct RequestIdentifier: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard let uuid = UUID(uuidString: rawValue) else { return nil }
        self.rawValue = uuid.uuidString.lowercased()
    }

    public init(_ uuid: UUID) {
        self.rawValue = uuid.uuidString.lowercased()
    }

    public var uuid: UUID {
        // Construction guarantees this conversion.
        UUID(uuidString: rawValue)!
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Request identifier must be a UUID."
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct RequestNonce: RawRepresentable, Hashable, Codable, Sendable, CustomStringConvertible {
    public let rawValue: String

    public init?(rawValue: String) {
        guard (16...128).contains(rawValue.count) else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard rawValue.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        self.rawValue = rawValue
    }

    public var description: String { rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let value = Self(rawValue: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Request nonce does not satisfy the Saturn contract."
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public typealias WorkloadIdentifier = SaturnNodeIdentifier
public typealias DeploymentIdentifier = SaturnNodeIdentifier
public typealias ModelIdentifier = SaturnNodeIdentifier
public typealias CredentialIdentifier = SaturnNodeIdentifier
