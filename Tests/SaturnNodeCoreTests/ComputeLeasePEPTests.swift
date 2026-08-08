import XCTest
import SaturnAuthority
@testable import SaturnNodeCore

final class ComputeLeasePEPTests: XCTestCase {
    private let pep = ComputeLeasePEP()

    func testValidLeasePasses() throws {
        let now = Date(timeIntervalSince1970: 1_775_548_800) // fixed
        let expiry = now.addingTimeInterval(1_800)
        let (lease, expected) = try makeLease(nodeID: "node-01", modelID: "mlx-default", now: now, expiry: expiry)
        try pep.verify(lease: lease, expected: expected, at: now)
    }

    func testExpiredLeaseFails() throws {
        let now = Date(timeIntervalSince1970: 1_775_548_800)
        let expiry = now.addingTimeInterval(-60)
        let (lease, expected) = try makeLease(nodeID: "node-01", modelID: "mlx-default", now: now.addingTimeInterval(-120), expiry: expiry)
        XCTAssertThrowsError(try pep.verify(lease: lease, expected: expected, at: now)) { error in
            XCTAssertEqual(error as? SaturnNodeError, .expiredCredential)
        }
    }

    func testNodeMismatchFails() throws {
        let now = Date(timeIntervalSince1970: 1_775_548_800)
        let expiry = now.addingTimeInterval(1_800)
        let (lease, _) = try makeLease(nodeID: "node-01", modelID: "mlx-default", now: now, expiry: expiry)
        guard let localNode = SaturnNodeIdentifier(rawValue: "node-02"),
              let model = ModelIdentifier(rawValue: "mlx-default") else {
            return XCTFail("identifiers")
        }
        XCTAssertThrowsError(try pep.verifyBoundToNode(lease: lease, nodeID: localNode, modelID: model, at: now)) { error in
            XCTAssertEqual(error as? SaturnNodeError, .wrongNode)
        }
    }

    func testModelMismatchFails() throws {
        let now = Date(timeIntervalSince1970: 1_775_548_800)
        let expiry = now.addingTimeInterval(1_800)
        let (lease, _) = try makeLease(nodeID: "node-01", modelID: "mlx-default", now: now, expiry: expiry)
        guard let localNode = SaturnNodeIdentifier(rawValue: "node-01"),
              let model = ModelIdentifier(rawValue: "other-model") else {
            return XCTFail("identifiers")
        }
        XCTAssertThrowsError(try pep.verifyBoundToNode(lease: lease, nodeID: localNode, modelID: model, at: now)) { error in
            XCTAssertEqual(error as? SaturnNodeError, .modelNotAllowed)
        }
    }

    func testFingerprintMaterialChangeFails() throws {
        let now = Date(timeIntervalSince1970: 1_775_548_800)
        let expiry = now.addingTimeInterval(1_800)
        let (lease, expected) = try makeLease(nodeID: "node-01", modelID: "mlx-default", now: now, expiry: expiry)
        let altered = AuthorityFingerprint(
            actorID: expected.actorID,
            actionID: expected.actionID,
            resourceID: expected.resourceID,
            operationID: expected.operationID,
            deploymentID: expected.deploymentID,
            workloadID: expected.workloadID,
            imageDigest: "sha256:different",
            runnerID: expected.runnerID,
            nodeID: expected.nodeID,
            modelID: expected.modelID,
            toolOrResourceID: expected.toolOrResourceID,
            dataClassification: expected.dataClassification,
            resourceLimits: expected.resourceLimits,
            computeLimits: expected.computeLimits,
            approvalReference: expected.approvalReference,
            policyVersion: expected.policyVersion,
            policyBundleDigest: expected.policyBundleDigest,
            issuedAt: expected.issuedAt,
            expiry: expected.expiry,
            nonce: expected.nonce,
            bindingAlgorithm: expected.bindingAlgorithm,
            keyID: expected.keyID
        )
        XCTAssertThrowsError(try pep.verify(lease: lease, expected: altered, at: now))
    }

    // MARK: - Fixtures

    private func makeLease(
        nodeID: String,
        modelID: String,
        now: Date,
        expiry: Date
    ) throws -> (ComputeLease, AuthorityFingerprint) {
        let issuedAt = iso(now)
        let expiryStr = iso(expiry)
        let fingerprint = AuthorityFingerprint(
            actorID: "saturn-node",
            actionID: "model.infer.local",
            resourceID: "task-001",
            operationID: "task-001",
            deploymentID: "saturn-control",
            workloadID: "task-001",
            imageDigest: "sha256:not-applicable",
            runnerID: "control-plane",
            nodeID: nodeID,
            modelID: modelID,
            toolOrResourceID: nil,
            dataClassification: "internal",
            resourceLimits: [:],
            computeLimits: ["context": "8192", "output": "2048"],
            approvalReference: nil,
            policyVersion: "0.1.0-proposal",
            policyBundleDigest: "sha256:development-bundle-not-signed",
            issuedAt: issuedAt,
            expiry: expiryStr,
            nonce: "nonce-test-001",
            bindingAlgorithm: "ed25519",
            keyID: "dev-unsigned"
        )
        let lease = try DefaultAuthorityIssuer().issueLease(
            fingerprint: fingerprint,
            nodeID: nodeID,
            modelID: modelID,
            contextLimit: 8192,
            outputLimit: 2048,
            concurrencyLimit: 1,
            budget: nil,
            sealAlgorithm: "ed25519",
            sealValue: "dev-unsigned",
            issuedAt: issuedAt,
            expiry: expiryStr
        )
        return (lease, fingerprint)
    }

    private func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}
