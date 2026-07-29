import Foundation

public struct SaturnNodeInferenceRequest: Hashable, Sendable {
    public let requestID: RequestIdentifier
    public let deploymentID: DeploymentIdentifier
    public let workloadID: WorkloadIdentifier
    public let modelID: ModelIdentifier
    public let prompt: String
    public let maximumOutputTokens: Int

    public init(
        requestID: RequestIdentifier,
        deploymentID: DeploymentIdentifier,
        workloadID: WorkloadIdentifier,
        modelID: ModelIdentifier,
        prompt: String,
        maximumOutputTokens: Int
    ) throws {
        guard !prompt.isEmpty else { throw SaturnNodeError.emptyPrompt }
        guard maximumOutputTokens > 0 else {
            throw SaturnNodeError.invalidOutputLimit
        }
        self.requestID = requestID
        self.deploymentID = deploymentID
        self.workloadID = workloadID
        self.modelID = modelID
        self.prompt = prompt
        self.maximumOutputTokens = maximumOutputTokens
    }
}

public enum SaturnNodeInferenceEvent: Hashable, Sendable {
    case started(modelID: ModelIdentifier)
    case textDelta(String)
    case usage(inputTokens: Int, outputTokens: Int)
    case completed
}

public protocol SaturnNodeInferenceRuntime: Sendable {
    func capabilities() async throws -> SaturnNodeRuntimeCapabilities
    func stream(
        request: SaturnNodeInferenceRequest
    ) -> AsyncThrowingStream<SaturnNodeInferenceEvent, Error>
}

public struct SaturnNodeRuntimeCapabilities: Hashable, Codable, Sendable {
    public let nodeID: SaturnNodeIdentifier
    public let modelIDs: [ModelIdentifier]
    public let maximumConcurrentRequests: Int

    public init(
        nodeID: SaturnNodeIdentifier,
        modelIDs: [ModelIdentifier],
        maximumConcurrentRequests: Int
    ) throws {
        guard !modelIDs.isEmpty, maximumConcurrentRequests > 0 else {
            throw SaturnNodeError.invalidRuntimeCapabilities
        }
        self.nodeID = nodeID
        self.modelIDs = modelIDs
        self.maximumConcurrentRequests = maximumConcurrentRequests
    }
}

public struct UnavailableInferenceRuntime: SaturnNodeInferenceRuntime {
    public init() {}

    public func capabilities() async throws -> SaturnNodeRuntimeCapabilities {
        throw SaturnNodeError.runtimeUnavailable
    }

    public func stream(
        request: SaturnNodeInferenceRequest
    ) -> AsyncThrowingStream<SaturnNodeInferenceEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: SaturnNodeError.runtimeUnavailable)
        }
    }
}
