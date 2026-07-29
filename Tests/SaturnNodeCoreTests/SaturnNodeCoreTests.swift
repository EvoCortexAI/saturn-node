import Foundation
import Testing
@testable import SaturnNodeCore

private func id(_ value: String) throws -> SaturnNodeIdentifier {
    try #require(SaturnNodeIdentifier(rawValue: value))
}

@Test("Manifest rejects duplicate model identifiers")
func manifestRejectsDuplicateModels() throws {
    let nodeID = try id("saturn-node-01")
    let modelID = try id("local-model")
    let runtime = try SaturnNodeModelManifest.RuntimeDescriptor(
        name: "test-runtime",
        revision: "test-revision"
    )
    let model = try SaturnNodeModelManifest.ModelDescriptor(
        id: modelID,
        artifact: "local/test-model",
        revision: "test-model-revision",
        maximumContextTokens: 4096,
        maximumOutputTokens: 1024
    )

    #expect(throws: SaturnNodeError.duplicateModelIdentifier) {
        _ = try SaturnNodeModelManifest(
            schemaVersion: 1,
            nodeID: nodeID,
            runtime: runtime,
            models: [model, model]
        )
    }
}

@Test("Workload claims are bound to node, model, epoch, time, and limits")
func validatesBoundClaims() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let nodeID = try id("saturn-node-01")
    let modelID = try id("local-model")
    let claims = try WorkloadComputeClaims(
        credentialID: try id("credential-01"),
        workloadID: try id("workload-01"),
        deploymentID: try id("deployment-01"),
        nodeID: nodeID,
        modelID: modelID,
        maximumContextTokens: 4096,
        maximumOutputTokens: 1024,
        maximumConcurrentRequests: 1,
        requestBudget: 10,
        issuedAt: now.addingTimeInterval(-60),
        expiresAt: now.addingTimeInterval(300),
        epoch: 4,
        policyReference: "policy-test"
    )
    let context = WorkloadAuthorizationContext(
        expectedNodeID: nodeID,
        requestedModelID: modelID,
        requestedContextTokens: 2048,
        requestedOutputTokens: 512,
        acceptedEpoch: 4,
        clockSkewAllowance: 5
    )

    try WorkloadClaimValidator.validate(claims: claims, context: context, now: now)
}

@Test("Expired claims fail closed")
func expiredClaimsFailClosed() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let nodeID = try id("saturn-node-01")
    let modelID = try id("local-model")
    let claims = try WorkloadComputeClaims(
        credentialID: try id("credential-01"),
        workloadID: try id("workload-01"),
        deploymentID: try id("deployment-01"),
        nodeID: nodeID,
        modelID: modelID,
        maximumContextTokens: 4096,
        maximumOutputTokens: 1024,
        maximumConcurrentRequests: 1,
        requestBudget: 10,
        issuedAt: now.addingTimeInterval(-600),
        expiresAt: now.addingTimeInterval(-60),
        epoch: 4
    )
    let context = WorkloadAuthorizationContext(
        expectedNodeID: nodeID,
        requestedModelID: modelID,
        requestedContextTokens: 2048,
        requestedOutputTokens: 512,
        acceptedEpoch: 4,
        clockSkewAllowance: 5
    )

    #expect(throws: SaturnNodeError.expiredCredential) {
        try WorkloadClaimValidator.validate(claims: claims, context: context, now: now)
    }
}

@Test("Bootstrap runtime fails closed")
func unavailableRuntimeFailsClosed() async {
    let runtime = UnavailableInferenceRuntime()
    await #expect(throws: SaturnNodeError.runtimeUnavailable) {
        _ = try await runtime.capabilities()
    }
}
