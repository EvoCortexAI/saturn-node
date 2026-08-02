public enum SaturnNodeProblemCode: String, CaseIterable, Codable, Hashable, Sendable {
    case contractVersionUnsupported = "contract_version_unsupported"
    case malformedRequest = "malformed_request"
    case unauthenticated
    case unauthorized
    case wrongAudience = "wrong_audience"
    case wrongWorkload = "wrong_workload"
    case wrongDeployment = "wrong_deployment"
    case wrongNode = "wrong_node"
    case modelNotAllowed = "model_not_allowed"
    case credentialNotYetValid = "credential_not_yet_valid"
    case credentialExpired = "credential_expired"
    case credentialRevoked = "credential_revoked"
    case credentialReplayed = "credential_replayed"
    case staleCredentialEpoch = "stale_credential_epoch"
    case requestLimitExceeded = "request_limit_exceeded"
    case tokenBudgetExceeded = "token_budget_exceeded"
    case nodeSaturated = "node_saturated"
    case requestTimeout = "request_timeout"
    case cancelled
    case internalFailure = "internal_failure"
}

public enum SaturnNodeError: Error, Hashable, Sendable {
    case unsupportedManifestVersion(Int)
    case emptyModelAllowlist
    case duplicateModelIdentifier
    case invalidManifestValue(String)
    case unsupportedContractVersion(String)
    case malformedRequest(String)
    case invalidCredentialClaims
    case credentialVerificationUnavailable
    case unauthenticated
    case unauthorized
    case wrongAudience
    case wrongWorkload
    case wrongDeployment
    case revokedCredential
    case replayedCredential
    case wrongNode
    case modelNotAllowed
    case staleCredentialEpoch
    case credentialNotYetValid
    case expiredCredential
    case requestExceedsCredentialLimits
    case requestBudgetExceeded
    case tokenBudgetExceeded
    case emptyPrompt
    case invalidOutputLimit
    case invalidRuntimeCapabilities
    case runtimeUnavailable
    case nodeSaturated
    case requestTimedOut
    case cancelled
    case requestAlreadyTerminal
    // Composition / service seams
    case invalidServiceConfiguration(String)
    case identityUnavailable
    case revocationStateUnavailable
    case replayProtectionUnavailable
    case modelAllowlistUnavailable
    case admissionUnavailable
    case serviceDraining

    public var problemCode: SaturnNodeProblemCode {
        switch self {
        case .unsupportedContractVersion:
            .contractVersionUnsupported
        case .malformedRequest,
             .unsupportedManifestVersion,
             .emptyModelAllowlist,
             .duplicateModelIdentifier,
             .invalidManifestValue,
             .invalidCredentialClaims,
             .emptyPrompt,
             .invalidOutputLimit,
             .invalidRuntimeCapabilities,
             .invalidServiceConfiguration:
            .malformedRequest
        case .credentialVerificationUnavailable,
             .runtimeUnavailable,
             .requestAlreadyTerminal,
             .identityUnavailable,
             .revocationStateUnavailable,
             .replayProtectionUnavailable,
             .modelAllowlistUnavailable,
             .admissionUnavailable:
            .internalFailure
        case .unauthenticated:
            .unauthenticated
        case .unauthorized:
            .unauthorized
        case .wrongAudience:
            .wrongAudience
        case .wrongWorkload:
            .wrongWorkload
        case .wrongDeployment:
            .wrongDeployment
        case .wrongNode:
            .wrongNode
        case .modelNotAllowed:
            .modelNotAllowed
        case .credentialNotYetValid:
            .credentialNotYetValid
        case .expiredCredential:
            .credentialExpired
        case .revokedCredential:
            .credentialRevoked
        case .replayedCredential:
            .credentialReplayed
        case .staleCredentialEpoch:
            .staleCredentialEpoch
        case .requestExceedsCredentialLimits,
             .requestBudgetExceeded:
            .requestLimitExceeded
        case .tokenBudgetExceeded:
            .tokenBudgetExceeded
        case .nodeSaturated,
             .serviceDraining:
            .nodeSaturated
        case .requestTimedOut:
            .requestTimeout
        case .cancelled:
            .cancelled
        }
    }
}
