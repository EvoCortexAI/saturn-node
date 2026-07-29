import Foundation

public struct WorkloadComputeClaims: Hashable, Codable, Sendable {
    public static let supportedContractVersion = "1"
    public static let trustedIssuer = "saturn-control"

    public let contractVersion: String
    public let credentialID: CredentialIdentifier
    public let issuer: String
    public let audience: String
    public let workloadID: WorkloadIdentifier
    public let deploymentID: DeploymentIdentifier
    public let nodeID: SaturnNodeIdentifier
    public let modelID: ModelIdentifier
    public let maximumContextTokens: Int
    public let maximumOutputTokens: Int
    public let maximumConcurrentRequests: Int
    public let requestBudget: Int
    public let tokenBudget: Int
    public let issuedAt: Date
    public let notBefore: Date
    public let expiresAt: Date
    public let epoch: Int
    public let policyReference: String?
    public let approvalReference: String?

    private enum CodingKeys: String, CodingKey {
        case contractVersion
        case credentialID = "credentialId"
        case issuer
        case audience
        case workloadID = "workloadId"
        case deploymentID = "deploymentId"
        case nodeID = "nodeId"
        case modelID = "modelId"
        case maximumContextTokens
        case maximumOutputTokens
        case maximumConcurrentRequests
        case requestBudget
        case tokenBudget
        case issuedAt
        case notBefore
        case expiresAt
        case epoch
        case policyReference
        case approvalReference
    }

    public init(
        contractVersion: String = Self.supportedContractVersion,
        credentialID: CredentialIdentifier,
        issuer: String = Self.trustedIssuer,
        audience: String,
        workloadID: WorkloadIdentifier,
        deploymentID: DeploymentIdentifier,
        nodeID: SaturnNodeIdentifier,
        modelID: ModelIdentifier,
        maximumContextTokens: Int,
        maximumOutputTokens: Int,
        maximumConcurrentRequests: Int,
        requestBudget: Int,
        tokenBudget: Int,
        issuedAt: Date,
        notBefore: Date,
        expiresAt: Date,
        epoch: Int,
        policyReference: String? = nil,
        approvalReference: String? = nil
    ) throws {
        guard contractVersion == Self.supportedContractVersion else {
            throw SaturnNodeError.unsupportedContractVersion(contractVersion)
        }
        guard issuer == Self.trustedIssuer else {
            throw SaturnNodeError.unauthenticated
        }
        guard audience == Self.audience(for: nodeID) else {
            throw SaturnNodeError.wrongAudience
        }
        guard maximumContextTokens > 0,
              maximumOutputTokens > 0,
              maximumOutputTokens <= maximumContextTokens,
              maximumConcurrentRequests > 0,
              requestBudget > 0,
              tokenBudget > 0,
              issuedAt <= notBefore,
              notBefore < expiresAt,
              epoch >= 0 else {
            throw SaturnNodeError.invalidCredentialClaims
        }

        self.contractVersion = contractVersion
        self.credentialID = credentialID
        self.issuer = issuer
        self.audience = audience
        self.workloadID = workloadID
        self.deploymentID = deploymentID
        self.nodeID = nodeID
        self.modelID = modelID
        self.maximumContextTokens = maximumContextTokens
        self.maximumOutputTokens = maximumOutputTokens
        self.maximumConcurrentRequests = maximumConcurrentRequests
        self.requestBudget = requestBudget
        self.tokenBudget = tokenBudget
        self.issuedAt = issuedAt
        self.notBefore = notBefore
        self.expiresAt = expiresAt
        self.epoch = epoch
        self.policyReference = policyReference
        self.approvalReference = approvalReference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            contractVersion: container.decode(String.self, forKey: .contractVersion),
            credentialID: container.decode(CredentialIdentifier.self, forKey: .credentialID),
            issuer: container.decode(String.self, forKey: .issuer),
            audience: container.decode(String.self, forKey: .audience),
            workloadID: container.decode(WorkloadIdentifier.self, forKey: .workloadID),
            deploymentID: container.decode(DeploymentIdentifier.self, forKey: .deploymentID),
            nodeID: container.decode(SaturnNodeIdentifier.self, forKey: .nodeID),
            modelID: container.decode(ModelIdentifier.self, forKey: .modelID),
            maximumContextTokens: container.decode(Int.self, forKey: .maximumContextTokens),
            maximumOutputTokens: container.decode(Int.self, forKey: .maximumOutputTokens),
            maximumConcurrentRequests: container.decode(Int.self, forKey: .maximumConcurrentRequests),
            requestBudget: container.decode(Int.self, forKey: .requestBudget),
            tokenBudget: container.decode(Int.self, forKey: .tokenBudget),
            issuedAt: container.decode(Date.self, forKey: .issuedAt),
            notBefore: container.decode(Date.self, forKey: .notBefore),
            expiresAt: container.decode(Date.self, forKey: .expiresAt),
            epoch: container.decode(Int.self, forKey: .epoch),
            policyReference: container.decodeIfPresent(String.self, forKey: .policyReference),
            approvalReference: container.decodeIfPresent(String.self, forKey: .approvalReference)
        )
    }

    public static func audience(for nodeID: SaturnNodeIdentifier) -> String {
        "saturn-node:\(nodeID.rawValue)"
    }
}

public struct WorkloadAuthorizationContext: Hashable, Sendable {
    public let expectedNodeID: SaturnNodeIdentifier
    public let expectedWorkloadID: WorkloadIdentifier
    public let expectedDeploymentID: DeploymentIdentifier
    public let requestedModelID: ModelIdentifier
    public let acceptedEpoch: Int
    public let clockSkewAllowance: TimeInterval
    public let activeConcurrentRequests: Int
    public let consumedRequestCount: Int
    public let consumedTokenCount: Int
    public let revokedCredentialIDs: Set<CredentialIdentifier>
    public let seenRequestIDs: Set<RequestIdentifier>
    public let seenRequestNonces: Set<RequestNonce>

    public init(
        expectedNodeID: SaturnNodeIdentifier,
        expectedWorkloadID: WorkloadIdentifier,
        expectedDeploymentID: DeploymentIdentifier,
        requestedModelID: ModelIdentifier,
        acceptedEpoch: Int,
        clockSkewAllowance: TimeInterval,
        activeConcurrentRequests: Int = 0,
        consumedRequestCount: Int = 0,
        consumedTokenCount: Int = 0,
        revokedCredentialIDs: Set<CredentialIdentifier> = [],
        seenRequestIDs: Set<RequestIdentifier> = [],
        seenRequestNonces: Set<RequestNonce> = []
    ) {
        self.expectedNodeID = expectedNodeID
        self.expectedWorkloadID = expectedWorkloadID
        self.expectedDeploymentID = expectedDeploymentID
        self.requestedModelID = requestedModelID
        self.acceptedEpoch = max(0, acceptedEpoch)
        self.clockSkewAllowance = max(0, clockSkewAllowance)
        self.activeConcurrentRequests = max(0, activeConcurrentRequests)
        self.consumedRequestCount = max(0, consumedRequestCount)
        self.consumedTokenCount = max(0, consumedTokenCount)
        self.revokedCredentialIDs = revokedCredentialIDs
        self.seenRequestIDs = seenRequestIDs
        self.seenRequestNonces = seenRequestNonces
    }
}

public enum WorkloadClaimValidator {
    public static func validate(
        claims: WorkloadComputeClaims,
        request: SaturnNodeInferenceRequest,
        context: WorkloadAuthorizationContext,
        now: Date
    ) throws {
        guard claims.contractVersion == WorkloadComputeClaims.supportedContractVersion else {
            throw SaturnNodeError.unsupportedContractVersion(claims.contractVersion)
        }
        guard claims.issuer == WorkloadComputeClaims.trustedIssuer else {
            throw SaturnNodeError.unauthenticated
        }
        guard claims.audience == WorkloadComputeClaims.audience(for: context.expectedNodeID) else {
            throw SaturnNodeError.wrongAudience
        }
        guard !context.revokedCredentialIDs.contains(claims.credentialID) else {
            throw SaturnNodeError.revokedCredential
        }
        guard !context.seenRequestIDs.contains(request.requestID),
              !context.seenRequestNonces.contains(request.requestNonce) else {
            throw SaturnNodeError.replayedCredential
        }
        guard claims.nodeID == context.expectedNodeID else {
            throw SaturnNodeError.wrongNode
        }
        guard claims.workloadID == context.expectedWorkloadID,
              request.workloadID == context.expectedWorkloadID else {
            throw SaturnNodeError.wrongWorkload
        }
        guard claims.deploymentID == context.expectedDeploymentID,
              request.deploymentID == context.expectedDeploymentID else {
            throw SaturnNodeError.wrongDeployment
        }
        guard claims.modelID == context.requestedModelID,
              request.modelID == context.requestedModelID else {
            throw SaturnNodeError.modelNotAllowed
        }
        guard claims.epoch == context.acceptedEpoch else {
            throw SaturnNodeError.staleCredentialEpoch
        }
        guard now.addingTimeInterval(context.clockSkewAllowance) >= claims.notBefore else {
            throw SaturnNodeError.credentialNotYetValid
        }
        guard now.addingTimeInterval(-context.clockSkewAllowance) < claims.expiresAt else {
            throw SaturnNodeError.expiredCredential
        }
        guard request.maximumContextTokens <= claims.maximumContextTokens,
              request.maximumOutputTokens <= claims.maximumOutputTokens else {
            throw SaturnNodeError.requestExceedsCredentialLimits
        }
        guard context.activeConcurrentRequests < claims.maximumConcurrentRequests,
              context.consumedRequestCount < claims.requestBudget else {
            throw SaturnNodeError.requestBudgetExceeded
        }

        let requestedTokenBudget = request.maximumContextTokens + request.maximumOutputTokens
        guard context.consumedTokenCount + requestedTokenBudget <= claims.tokenBudget else {
            throw SaturnNodeError.tokenBudgetExceeded
        }
        guard request.deadlineAt > now else {
            throw SaturnNodeError.requestTimedOut
        }
    }
}

public protocol WorkloadCredentialVerifying: Sendable {
    func verify(presentation: Data) async throws -> WorkloadComputeClaims
}

public struct UnavailableWorkloadCredentialVerifier: WorkloadCredentialVerifying {
    public init() {}

    public func verify(presentation: Data) async throws -> WorkloadComputeClaims {
        throw SaturnNodeError.credentialVerificationUnavailable
    }
}
