import Foundation

public struct SaturnNodeModelManifest: Hashable, Codable, Sendable {
    public let schemaVersion: Int
    public let nodeID: SaturnNodeIdentifier
    public let runtime: RuntimeDescriptor
    public let models: [ModelDescriptor]

    public init(
        schemaVersion: Int,
        nodeID: SaturnNodeIdentifier,
        runtime: RuntimeDescriptor,
        models: [ModelDescriptor]
    ) throws {
        guard schemaVersion == 1 else {
            throw SaturnNodeError.unsupportedManifestVersion(schemaVersion)
        }
        guard !models.isEmpty else {
            throw SaturnNodeError.emptyModelAllowlist
        }
        guard Set(models.map(\.id)).count == models.count else {
            throw SaturnNodeError.duplicateModelIdentifier
        }

        self.schemaVersion = schemaVersion
        self.nodeID = nodeID
        self.runtime = runtime
        self.models = models
    }

    public func model(id: ModelIdentifier) -> ModelDescriptor? {
        models.first { $0.id == id }
    }

    public struct RuntimeDescriptor: Hashable, Codable, Sendable {
        public let name: String
        public let revision: String

        public init(name: String, revision: String) throws {
            guard !name.isEmpty, name.count <= 128 else {
                throw SaturnNodeError.invalidManifestValue("runtime.name")
            }
            guard !revision.isEmpty, revision.count <= 256 else {
                throw SaturnNodeError.invalidManifestValue("runtime.revision")
            }
            self.name = name
            self.revision = revision
        }
    }

    public struct ModelDescriptor: Hashable, Codable, Sendable {
        public let id: ModelIdentifier
        public let artifact: String
        public let revision: String
        public let maximumContextTokens: Int
        public let maximumOutputTokens: Int

        public init(
            id: ModelIdentifier,
            artifact: String,
            revision: String,
            maximumContextTokens: Int,
            maximumOutputTokens: Int
        ) throws {
            guard !artifact.isEmpty, artifact.count <= 512 else {
                throw SaturnNodeError.invalidManifestValue("models.artifact")
            }
            guard !revision.isEmpty, revision.count <= 256 else {
                throw SaturnNodeError.invalidManifestValue("models.revision")
            }
            guard maximumContextTokens > 0 else {
                throw SaturnNodeError.invalidManifestValue("models.maximumContextTokens")
            }
            guard maximumOutputTokens > 0,
                  maximumOutputTokens <= maximumContextTokens else {
                throw SaturnNodeError.invalidManifestValue("models.maximumOutputTokens")
            }

            self.id = id
            self.artifact = artifact
            self.revision = revision
            self.maximumContextTokens = maximumContextTokens
            self.maximumOutputTokens = maximumOutputTokens
        }
    }
}
