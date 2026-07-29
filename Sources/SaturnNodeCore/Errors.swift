public enum SaturnNodeError: Error, Hashable, Sendable {
    case unsupportedManifestVersion(Int)
    case emptyModelAllowlist
    case duplicateModelIdentifier
    case invalidManifestValue(String)
    case invalidCredentialClaims
    case credentialVerificationUnavailable
    case revokedCredential
    case wrongNode
    case modelNotAllowed
    case staleCredentialEpoch
    case credentialNotYetValid
    case expiredCredential
    case requestExceedsCredentialLimits
    case emptyPrompt
    case invalidOutputLimit
    case invalidRuntimeCapabilities
    case runtimeUnavailable
}
