import Foundation

public struct WorkloadComputeClaims: Hashable, Codable, Sendable {
    public let credentialID: CredentialIdentifier
    public let workloadID: WorkloadIdentifier
    public let deploymentID: DeploymentIdentifier
    public let nodeID: SaturnNodeIdentifier
    public let modelID: ModelIdentifier
    public let maximumContextTokens: Int
    public let maximumOutputTokens: Int
    public let maximumConcurrentRequests: Int
    public let requestBudget: Int
    public let issuedAt: Date
    public let expiresAt: Date
    public let epoch: Int
    public let policyReference: String?

    public init(
        credentialID: CredentialIdentifier,
        workloadID: WorkloadIdentifier,
        deploymentID: DeploymentIdentifier,
        nodeID: SaturnNodeIdentifier,
        modelID: ModelIdentifier,
        maximumContextTokens: Int,
        maximumOutputTokens: Int,
        maximumConcurrentRequests: Int,
        requestBudget: Int,
        issuedAt: Date,
        expiresAt: Date,
        epoch: Int,
        policyReference: String? = nil
    ) throws {
        guard maximumContextTokens > 0,
              maximumOutputTokens > 0,
              maximumOutputTokens <= maximumContextTokens,
              maximumConcurrentRequests > 0,
              requestBudget > 0,
              issuedAt < expiresAt,
              epoch >= 0 else {
            throw SaturnNodeError.invalidCredentialClaims
        }

        self.credentialID = credentialID
        self.workloadID = workloadID
        self.deploymentID = deploymentID
        self.nodeID = nodeID
        self.modelID = modelID
        self.maximumContextTokens = maximumContextTokens
        self.maximumOutputTokens = maximumOutputTokens
        self.maximumConcurrentRequests = maximumConcurrentRequests
        self.requestBudget = requestBudget
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.epoch = epoch
        self.policyReference = policyReference
    }
}

public struct WorkloadAuthorizationContext: Hashable, Sendable {
    public let expectedNodeID: SaturnNodeIdentifier
    public let requestedModelID: ModelIdentifier
    public let requestedContextTokens: Int
    public let requestedOutputTokens: Int
    public let acceptedEpoch: Int
    public let clockSkewAllowance: TimeInterval

    public init(
        expectedNodeID: SaturnNodeIdentifier,
        requestedModelID: ModelIdentifier,
        requestedContextTokens: Int,
        requestedOutputTokens: Int,
        acceptedEpoch: Int,
        clockSkewAllowance: TimeInterval
    ) {
        self.expectedNodeID = expectedNodeID
        self.requestedModelID = requestedModelID
        self.requestedContextTokens = requestedContextTokens
        self.requestedOutputTokens = requestedOutputTokens
        self.acceptedEpoch = acceptedEpoch
        self.clockSkewAllowance = max(0, clockSkewAllowance)
    }
}

public enum WorkloadClaimValidator {
    public static func validate(
        claims: WorkloadComputeClaims,
        context: WorkloadAuthorizationContext,
        now: Date,
        revokedCredentialIDs: Set<CredentialIdentifier> = []
    ) throws {
        guard !revokedCredentialIDs.contains(claims.credentialID) else {
            throw SaturnNodeError.revokedCredential
        }
        guard claims.nodeID == context.expectedNodeID else {
            throw SaturnNodeError.wrongNode
        }
        guard claims.modelID == context.requestedModelID else {
            throw SaturnNodeError.modelNotAllowed
        }
        guard claims.epoch == context.acceptedEpoch else {
            throw SaturnNodeError.staleCredentialEpoch
        }
        guard now.addingTimeInterval(context.clockSkewAllowance) >= claims.issuedAt else {
            throw SaturnNodeError.credentialNotYetValid
        }
        guard now.addingTimeInterval(-context.clockSkewAllowance) < claims.expiresAt else {
            throw SaturnNodeError.expiredCredential
        }
        guard context.requestedContextTokens <= claims.maximumContextTokens,
              context.requestedOutputTokens <= claims.maximumOutputTokens else {
            throw SaturnNodeError.requestExceedsCredentialLimits
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
