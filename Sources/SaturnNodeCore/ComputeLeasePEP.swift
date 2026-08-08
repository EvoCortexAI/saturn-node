import Foundation
import SaturnAuthority

/// Final Policy Enforcement Point for inference compute (SUA §8.3 / G2).
///
/// Saturn-Node verifies Control-issued `ComputeLease` material **before** entering
/// MLX execution. It never issues authority. Cryptographic seal verification is
/// deployment-specific and layered on top of structural checks when production
/// keys are configured.
public struct ComputeLeasePEP: Sendable {
    private let verifier: StructuralAuthorityVerifier

    public init(verifier: StructuralAuthorityVerifier = StructuralAuthorityVerifier()) {
        self.verifier = verifier
    }

    /// Fail closed on forged, expired, node/model-mismatched, or structurally invalid leases.
    public func verify(
        lease: ComputeLease,
        expected: AuthorityFingerprint,
        at now: Date = Date()
    ) throws {
        do {
            try verifier.verify(lease: lease, expected: expected, at: now)
        } catch let error as AuthorityError {
            throw mapAuthorityError(error)
        } catch {
            throw SaturnNodeError.unauthorized
        }
    }

    /// Convenience: build expected fingerprint from node-local facts + lease fingerprint skeleton.
    /// Material fields on `lease.fingerprint` must match; this rejects node/model drift.
    public func verifyBoundToNode(
        lease: ComputeLease,
        nodeID: SaturnNodeIdentifier,
        modelID: ModelIdentifier,
        at now: Date = Date()
    ) throws {
        var expected = lease.fingerprint
        // Reconstruct expected with local node/model — StructuralAuthorityVerifier requires exact match.
        expected = AuthorityFingerprint(
            actorID: lease.fingerprint.actorID,
            actionID: lease.fingerprint.actionID,
            resourceID: lease.fingerprint.resourceID,
            operationID: lease.fingerprint.operationID,
            deploymentID: lease.fingerprint.deploymentID,
            workloadID: lease.fingerprint.workloadID,
            imageDigest: lease.fingerprint.imageDigest,
            runnerID: lease.fingerprint.runnerID,
            nodeID: nodeID.rawValue,
            modelID: modelID.rawValue,
            toolOrResourceID: lease.fingerprint.toolOrResourceID,
            dataClassification: lease.fingerprint.dataClassification,
            resourceLimits: lease.fingerprint.resourceLimits,
            computeLimits: lease.fingerprint.computeLimits,
            approvalReference: lease.fingerprint.approvalReference,
            policyVersion: lease.fingerprint.policyVersion,
            policyBundleDigest: lease.fingerprint.policyBundleDigest,
            issuedAt: lease.fingerprint.issuedAt,
            expiry: lease.fingerprint.expiry,
            nonce: lease.fingerprint.nonce,
            bindingAlgorithm: lease.fingerprint.bindingAlgorithm,
            keyID: lease.fingerprint.keyID
        )

        if lease.nodeID != nodeID.rawValue {
            throw SaturnNodeError.wrongNode
        }
        if lease.modelID != modelID.rawValue {
            throw SaturnNodeError.modelNotAllowed
        }

        try verify(lease: lease, expected: expected, at: now)
    }

    private func mapAuthorityError(_ error: AuthorityError) -> SaturnNodeError {
        switch error {
        case .expired:
            return .expiredCredential
        case .replayDetected:
            return .replayedCredential
        case .scopeMismatch:
            return .unauthorized
        case .sealVerificationFailed:
            return .unauthorized
        case .policyDowngrade:
            return .unauthorized
        case .revoked:
            return .revokedCredential
        case .invalidFingerprint, .unsupportedVersion, .missingRequiredField:
            return .malformedRequest("compute lease")
        }
    }
}
