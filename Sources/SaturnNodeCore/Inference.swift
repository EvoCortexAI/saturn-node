import Foundation

public struct SaturnNodeInferenceRequest: Hashable, Codable, Sendable {
    public static let supportedContractVersion = "1"

    public let contractVersion: String
    public let requestID: RequestIdentifier
    public let requestNonce: RequestNonce
    public let deploymentID: DeploymentIdentifier
    public let workloadID: WorkloadIdentifier
    public let modelID: ModelIdentifier
    public let inputText: String
    public let maximumContextTokens: Int
    public let maximumOutputTokens: Int
    public let deadlineAt: Date

    private enum CodingKeys: String, CodingKey {
        case contractVersion
        case requestID = "requestId"
        case requestNonce
        case deploymentID = "deploymentId"
        case workloadID = "workloadId"
        case modelID = "modelId"
        case inputText
        case maximumContextTokens
        case maximumOutputTokens
        case deadlineAt
    }

    public init(
        contractVersion: String = Self.supportedContractVersion,
        requestID: RequestIdentifier,
        requestNonce: RequestNonce,
        deploymentID: DeploymentIdentifier,
        workloadID: WorkloadIdentifier,
        modelID: ModelIdentifier,
        inputText: String,
        maximumContextTokens: Int,
        maximumOutputTokens: Int,
        deadlineAt: Date
    ) throws {
        guard contractVersion == Self.supportedContractVersion else {
            throw SaturnNodeError.unsupportedContractVersion(contractVersion)
        }
        guard !inputText.isEmpty, inputText.count <= 1_000_000 else {
            throw SaturnNodeError.emptyPrompt
        }
        guard maximumContextTokens > 0,
              maximumContextTokens <= 1_048_576,
              maximumOutputTokens > 0,
              maximumOutputTokens <= 65_536,
              maximumOutputTokens <= maximumContextTokens else {
            throw SaturnNodeError.invalidOutputLimit
        }

        self.contractVersion = contractVersion
        self.requestID = requestID
        self.requestNonce = requestNonce
        self.deploymentID = deploymentID
        self.workloadID = workloadID
        self.modelID = modelID
        self.inputText = inputText
        self.maximumContextTokens = maximumContextTokens
        self.maximumOutputTokens = maximumOutputTokens
        self.deadlineAt = deadlineAt
    }

    public var prompt: String { inputText }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            contractVersion: container.decode(String.self, forKey: .contractVersion),
            requestID: container.decode(RequestIdentifier.self, forKey: .requestID),
            requestNonce: container.decode(RequestNonce.self, forKey: .requestNonce),
            deploymentID: container.decode(DeploymentIdentifier.self, forKey: .deploymentID),
            workloadID: container.decode(WorkloadIdentifier.self, forKey: .workloadID),
            modelID: container.decode(ModelIdentifier.self, forKey: .modelID),
            inputText: container.decode(String.self, forKey: .inputText),
            maximumContextTokens: container.decode(Int.self, forKey: .maximumContextTokens),
            maximumOutputTokens: container.decode(Int.self, forKey: .maximumOutputTokens),
            deadlineAt: container.decode(Date.self, forKey: .deadlineAt)
        )
    }
}

public enum SaturnNodeRuntimeState: String, CaseIterable, Codable, Hashable, Sendable {
    case available
    case degraded
    case saturated
    case unavailable
}

public struct SaturnNodeModelCapability: Hashable, Codable, Sendable {
    public let modelID: ModelIdentifier
    public let maximumContextTokens: Int
    public let maximumOutputTokens: Int

    private enum CodingKeys: String, CodingKey {
        case modelID = "modelId"
        case maximumContextTokens
        case maximumOutputTokens
    }

    public init(
        modelID: ModelIdentifier,
        maximumContextTokens: Int,
        maximumOutputTokens: Int
    ) throws {
        guard maximumContextTokens > 0,
              maximumContextTokens <= 1_048_576,
              maximumOutputTokens > 0,
              maximumOutputTokens <= 65_536,
              maximumOutputTokens <= maximumContextTokens else {
            throw SaturnNodeError.invalidRuntimeCapabilities
        }
        self.modelID = modelID
        self.maximumContextTokens = maximumContextTokens
        self.maximumOutputTokens = maximumOutputTokens
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            modelID: container.decode(ModelIdentifier.self, forKey: .modelID),
            maximumContextTokens: container.decode(Int.self, forKey: .maximumContextTokens),
            maximumOutputTokens: container.decode(Int.self, forKey: .maximumOutputTokens)
        )
    }
}

public struct SaturnNodeRuntimeCapabilities: Hashable, Codable, Sendable {
    public let contractVersion: String
    public let nodeID: SaturnNodeIdentifier
    public let serviceVersion: String
    public let state: SaturnNodeRuntimeState
    public let models: [SaturnNodeModelCapability]
    public let maximumConcurrentRequests: Int
    public let acceptedCredentialEpoch: Int

    private enum CodingKeys: String, CodingKey {
        case contractVersion
        case nodeID = "nodeId"
        case serviceVersion
        case state
        case models
        case maximumConcurrentRequests
        case acceptedCredentialEpoch
    }

    public init(
        contractVersion: String = SaturnNodeInferenceRequest.supportedContractVersion,
        nodeID: SaturnNodeIdentifier,
        serviceVersion: String,
        state: SaturnNodeRuntimeState,
        models: [SaturnNodeModelCapability],
        maximumConcurrentRequests: Int,
        acceptedCredentialEpoch: Int
    ) throws {
        guard contractVersion == SaturnNodeInferenceRequest.supportedContractVersion else {
            throw SaturnNodeError.unsupportedContractVersion(contractVersion)
        }
        guard !serviceVersion.isEmpty,
              serviceVersion.count <= 64,
              !models.isEmpty,
              Set(models.map(\.modelID)).count == models.count,
              maximumConcurrentRequests > 0,
              acceptedCredentialEpoch >= 0 else {
            throw SaturnNodeError.invalidRuntimeCapabilities
        }
        self.contractVersion = contractVersion
        self.nodeID = nodeID
        self.serviceVersion = serviceVersion
        self.state = state
        self.models = models
        self.maximumConcurrentRequests = maximumConcurrentRequests
        self.acceptedCredentialEpoch = acceptedCredentialEpoch
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            contractVersion: container.decode(String.self, forKey: .contractVersion),
            nodeID: container.decode(SaturnNodeIdentifier.self, forKey: .nodeID),
            serviceVersion: container.decode(String.self, forKey: .serviceVersion),
            state: container.decode(SaturnNodeRuntimeState.self, forKey: .state),
            models: container.decode([SaturnNodeModelCapability].self, forKey: .models),
            maximumConcurrentRequests: container.decode(Int.self, forKey: .maximumConcurrentRequests),
            acceptedCredentialEpoch: container.decode(Int.self, forKey: .acceptedCredentialEpoch)
        )
    }

    public var modelIDs: [ModelIdentifier] {
        models.map(\.modelID)
    }
}

public enum SaturnNodeInferenceFinishReason: String, Codable, Hashable, Sendable {
    case stop
    case length
    case cancelled
}

public enum SaturnNodeInferenceEventType: String, Codable, Hashable, Sendable {
    case started
    case delta
    case usage
    case completed
    case cancelled
}

public enum SaturnNodeInferenceEvent: Hashable, Sendable {
    case started(
        requestID: RequestIdentifier,
        sequence: Int,
        nodeID: SaturnNodeIdentifier,
        modelID: ModelIdentifier
    )
    case delta(
        requestID: RequestIdentifier,
        sequence: Int,
        text: String
    )
    case usage(
        requestID: RequestIdentifier,
        sequence: Int,
        inputTokens: Int,
        outputTokens: Int
    )
    case completed(
        requestID: RequestIdentifier,
        sequence: Int,
        finishReason: SaturnNodeInferenceFinishReason
    )
    case cancelled(
        requestID: RequestIdentifier,
        sequence: Int
    )

    public var requestID: RequestIdentifier {
        switch self {
        case let .started(requestID, _, _, _),
             let .delta(requestID, _, _),
             let .usage(requestID, _, _, _),
             let .completed(requestID, _, _),
             let .cancelled(requestID, _):
            requestID
        }
    }

    public var sequence: Int {
        switch self {
        case let .started(_, sequence, _, _),
             let .delta(_, sequence, _),
             let .usage(_, sequence, _, _),
             let .completed(_, sequence, _),
             let .cancelled(_, sequence):
            sequence
        }
    }

    public var type: SaturnNodeInferenceEventType {
        switch self {
        case .started: .started
        case .delta: .delta
        case .usage: .usage
        case .completed: .completed
        case .cancelled: .cancelled
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .completed, .cancelled: true
        case .started, .delta, .usage: false
        }
    }
}

public struct SaturnNodeInferenceEventSequenceValidator: Hashable, Sendable {
    private var requestID: RequestIdentifier?
    private var nextSequence = 0
    private var hasStarted = false
    private var hasUsage = false
    private var isTerminal = false

    public init() {}

    public mutating func accept(_ event: SaturnNodeInferenceEvent) throws {
        guard !isTerminal else {
            throw SaturnNodeError.requestAlreadyTerminal
        }
        guard event.sequence == nextSequence else {
            throw SaturnNodeError.malformedRequest("Inference event sequence is not contiguous.")
        }
        if let requestID {
            guard requestID == event.requestID else {
                throw SaturnNodeError.malformedRequest("Inference event request IDs do not match.")
            }
        } else {
            requestID = event.requestID
        }

        switch event {
        case .started:
            guard !hasStarted, nextSequence == 0 else {
                throw SaturnNodeError.malformedRequest("Started must appear exactly once and first.")
            }
            hasStarted = true
        case .usage:
            guard hasStarted, !hasUsage else {
                throw SaturnNodeError.malformedRequest("Usage may appear at most once after started.")
            }
            hasUsage = true
        case .delta:
            guard hasStarted else {
                throw SaturnNodeError.malformedRequest("Delta appeared before started.")
            }
        case let .completed(_, _, finishReason):
            guard hasStarted, finishReason != .cancelled else {
                throw SaturnNodeError.malformedRequest("Completed has an invalid finish reason.")
            }
            isTerminal = true
        case .cancelled:
            guard hasStarted else {
                throw SaturnNodeError.malformedRequest("Cancelled appeared before started.")
            }
            isTerminal = true
        }

        nextSequence += 1
    }
}

public struct SaturnNodeUsageEvidence: Hashable, Codable, Sendable {
    public let contractVersion: String
    public let requestID: RequestIdentifier
    public let workloadID: WorkloadIdentifier
    public let deploymentID: DeploymentIdentifier
    public let nodeID: SaturnNodeIdentifier
    public let modelID: ModelIdentifier
    public let startedAt: Date
    public let completedAt: Date
    public let inputTokens: Int
    public let outputTokens: Int
    public let outcome: SaturnNodeUsageOutcome
    public let policyReference: String?
    public let approvalReference: String?

    private enum CodingKeys: String, CodingKey {
        case contractVersion
        case requestID = "requestId"
        case workloadID = "workloadId"
        case deploymentID = "deploymentId"
        case nodeID = "nodeId"
        case modelID = "modelId"
        case startedAt
        case completedAt
        case inputTokens
        case outputTokens
        case outcome
        case policyReference
        case approvalReference
    }

    public init(
        contractVersion: String = SaturnNodeInferenceRequest.supportedContractVersion,
        requestID: RequestIdentifier,
        workloadID: WorkloadIdentifier,
        deploymentID: DeploymentIdentifier,
        nodeID: SaturnNodeIdentifier,
        modelID: ModelIdentifier,
        startedAt: Date,
        completedAt: Date,
        inputTokens: Int,
        outputTokens: Int,
        outcome: SaturnNodeUsageOutcome,
        policyReference: String? = nil,
        approvalReference: String? = nil
    ) throws {
        guard contractVersion == SaturnNodeInferenceRequest.supportedContractVersion else {
            throw SaturnNodeError.unsupportedContractVersion(contractVersion)
        }
        guard completedAt >= startedAt,
              inputTokens >= 0,
              outputTokens >= 0 else {
            throw SaturnNodeError.malformedRequest("Usage evidence is invalid.")
        }
        self.contractVersion = contractVersion
        self.requestID = requestID
        self.workloadID = workloadID
        self.deploymentID = deploymentID
        self.nodeID = nodeID
        self.modelID = modelID
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.outcome = outcome
        self.policyReference = policyReference
        self.approvalReference = approvalReference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            contractVersion: container.decode(String.self, forKey: .contractVersion),
            requestID: container.decode(RequestIdentifier.self, forKey: .requestID),
            workloadID: container.decode(WorkloadIdentifier.self, forKey: .workloadID),
            deploymentID: container.decode(DeploymentIdentifier.self, forKey: .deploymentID),
            nodeID: container.decode(SaturnNodeIdentifier.self, forKey: .nodeID),
            modelID: container.decode(ModelIdentifier.self, forKey: .modelID),
            startedAt: container.decode(Date.self, forKey: .startedAt),
            completedAt: container.decode(Date.self, forKey: .completedAt),
            inputTokens: container.decode(Int.self, forKey: .inputTokens),
            outputTokens: container.decode(Int.self, forKey: .outputTokens),
            outcome: container.decode(SaturnNodeUsageOutcome.self, forKey: .outcome),
            policyReference: container.decodeIfPresent(String.self, forKey: .policyReference),
            approvalReference: container.decodeIfPresent(String.self, forKey: .approvalReference)
        )
    }
}

public enum SaturnNodeUsageOutcome: String, Codable, Hashable, Sendable {
    case completed
    case cancelled
    case failed
}

public enum SaturnNodeCancellationState: String, Codable, Hashable, Sendable {
    case cancellationRequested = "cancellation_requested"
    case cancelled
}

public struct SaturnNodeCancellationResponse: Hashable, Codable, Sendable {
    public let contractVersion: String
    public let requestID: RequestIdentifier
    public let state: SaturnNodeCancellationState

    private enum CodingKeys: String, CodingKey {
        case contractVersion
        case requestID = "requestId"
        case state
    }

    public init(
        contractVersion: String = SaturnNodeInferenceRequest.supportedContractVersion,
        requestID: RequestIdentifier,
        state: SaturnNodeCancellationState
    ) throws {
        guard contractVersion == SaturnNodeInferenceRequest.supportedContractVersion else {
            throw SaturnNodeError.unsupportedContractVersion(contractVersion)
        }
        self.contractVersion = contractVersion
        self.requestID = requestID
        self.state = state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            contractVersion: container.decode(String.self, forKey: .contractVersion),
            requestID: container.decode(RequestIdentifier.self, forKey: .requestID),
            state: container.decode(SaturnNodeCancellationState.self, forKey: .state)
        )
    }
}

public protocol SaturnNodeInferenceRuntime: Sendable {
    func capabilities() async throws -> SaturnNodeRuntimeCapabilities
    func stream(
        request: SaturnNodeInferenceRequest
    ) async throws -> AsyncThrowingStream<SaturnNodeInferenceEvent, Error>
    func cancel(requestID: RequestIdentifier) async throws
}

public struct UnavailableInferenceRuntime: SaturnNodeInferenceRuntime {
    public init() {}

    public func capabilities() async throws -> SaturnNodeRuntimeCapabilities {
        throw SaturnNodeError.runtimeUnavailable
    }

    public func stream(
        request: SaturnNodeInferenceRequest
    ) async throws -> AsyncThrowingStream<SaturnNodeInferenceEvent, Error> {
        throw SaturnNodeError.runtimeUnavailable
    }

    public func cancel(requestID: RequestIdentifier) async throws {
        throw SaturnNodeError.runtimeUnavailable
    }
}
