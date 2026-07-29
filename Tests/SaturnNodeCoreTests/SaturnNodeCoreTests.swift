import Foundation
import Testing
@testable import SaturnNodeCore

private struct ContractFixtures: Decodable {
    struct Valid: Decodable {
        let claims: WorkloadComputeClaims
        let capabilities: SaturnNodeRuntimeCapabilities
        let request: SaturnNodeInferenceRequest
        let usageEvidence: SaturnNodeUsageEvidence
        let cancellationResponse: SaturnNodeCancellationResponse
    }

    let contractVersion: String
    let validationNow: Date
    let valid: Valid
}

private func id(_ value: String) throws -> SaturnNodeIdentifier {
    try #require(SaturnNodeIdentifier(rawValue: value))
}

private func requestID(_ value: String) throws -> RequestIdentifier {
    try #require(RequestIdentifier(rawValue: value))
}

private func nonce(_ value: String) throws -> RequestNonce {
    try #require(RequestNonce(rawValue: value))
}

private func contractFixtures() throws -> ContractFixtures {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let fixtureURL = repositoryRoot
        .appendingPathComponent("docs")
        .appendingPathComponent("contracts")
        .appendingPathComponent("v1")
        .appendingPathComponent("fixtures.json")

    let data = try Data(contentsOf: fixtureURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(ContractFixtures.self, from: data)
}

private func replacementRequest(
    from request: SaturnNodeInferenceRequest,
    requestID: RequestIdentifier,
    requestNonce: RequestNonce
) throws -> SaturnNodeInferenceRequest {
    try SaturnNodeInferenceRequest(
        requestID: requestID,
        requestNonce: requestNonce,
        deploymentID: request.deploymentID,
        workloadID: request.workloadID,
        modelID: request.modelID,
        inputText: request.inputText,
        maximumContextTokens: request.maximumContextTokens,
        maximumOutputTokens: request.maximumOutputTokens,
        deadlineAt: request.deadlineAt
    )
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

@Test("Canonical v1 fixtures decode into validated Swift models")
func canonicalFixturesDecode() throws {
    let fixtures = try contractFixtures()

    #expect(fixtures.contractVersion == "1")
    #expect(fixtures.valid.claims.contractVersion == "1")
    #expect(fixtures.valid.request.contractVersion == "1")
    #expect(fixtures.valid.capabilities.nodeID == fixtures.valid.claims.nodeID)
    #expect(fixtures.valid.usageEvidence.requestID == fixtures.valid.request.requestID)
    #expect(fixtures.valid.cancellationResponse.requestID == fixtures.valid.request.requestID)
}

@Test("Canonical claims authorize the canonical bounded request")
func validatesCanonicalBoundClaims() throws {
    let fixtures = try contractFixtures()
    let claims = fixtures.valid.claims
    let request = fixtures.valid.request
    let context = WorkloadAuthorizationContext(
        expectedNodeID: claims.nodeID,
        expectedWorkloadID: claims.workloadID,
        expectedDeploymentID: claims.deploymentID,
        requestedModelID: claims.modelID,
        acceptedEpoch: claims.epoch,
        clockSkewAllowance: 30
    )

    try WorkloadClaimValidator.validate(
        claims: claims,
        request: request,
        context: context,
        now: fixtures.validationNow
    )
}

@Test("Expired claims fail closed")
func expiredClaimsFailClosed() throws {
    let fixtures = try contractFixtures()
    let original = fixtures.valid.claims
    let now = fixtures.validationNow
    let claims = try WorkloadComputeClaims(
        credentialID: original.credentialID,
        audience: original.audience,
        workloadID: original.workloadID,
        deploymentID: original.deploymentID,
        nodeID: original.nodeID,
        modelID: original.modelID,
        maximumContextTokens: original.maximumContextTokens,
        maximumOutputTokens: original.maximumOutputTokens,
        maximumConcurrentRequests: original.maximumConcurrentRequests,
        requestBudget: original.requestBudget,
        tokenBudget: original.tokenBudget,
        issuedAt: now.addingTimeInterval(-600),
        notBefore: now.addingTimeInterval(-600),
        expiresAt: now.addingTimeInterval(-60),
        epoch: original.epoch
    )
    let context = WorkloadAuthorizationContext(
        expectedNodeID: claims.nodeID,
        expectedWorkloadID: claims.workloadID,
        expectedDeploymentID: claims.deploymentID,
        requestedModelID: claims.modelID,
        acceptedEpoch: claims.epoch,
        clockSkewAllowance: 5
    )

    #expect(throws: SaturnNodeError.expiredCredential) {
        try WorkloadClaimValidator.validate(
            claims: claims,
            request: fixtures.valid.request,
            context: context,
            now: now
        )
    }
}

@Test("Wrong workload and replay facts fail closed")
func workloadAndReplayChecks() throws {
    let fixtures = try contractFixtures()
    let claims = fixtures.valid.claims
    let request = fixtures.valid.request
    let wrongWorkloadContext = WorkloadAuthorizationContext(
        expectedNodeID: claims.nodeID,
        expectedWorkloadID: try id("other-workload"),
        expectedDeploymentID: claims.deploymentID,
        requestedModelID: claims.modelID,
        acceptedEpoch: claims.epoch,
        clockSkewAllowance: 30
    )

    #expect(throws: SaturnNodeError.wrongWorkload) {
        try WorkloadClaimValidator.validate(
            claims: claims,
            request: request,
            context: wrongWorkloadContext,
            now: fixtures.validationNow
        )
    }

    let replayContext = WorkloadAuthorizationContext(
        expectedNodeID: claims.nodeID,
        expectedWorkloadID: claims.workloadID,
        expectedDeploymentID: claims.deploymentID,
        requestedModelID: claims.modelID,
        acceptedEpoch: claims.epoch,
        clockSkewAllowance: 30,
        seenRequestIDs: [request.requestID]
    )

    #expect(throws: SaturnNodeError.replayedCredential) {
        try WorkloadClaimValidator.validate(
            claims: claims,
            request: request,
            context: replayContext,
            now: fixtures.validationNow
        )
    }
}

@Test("Deterministic fake runtime streams one valid terminal sequence")
func fakeRuntimeStreamsDeterministically() async throws {
    let fixtures = try contractFixtures()
    let runtime = DeterministicFakeInferenceRuntime(
        capabilities: fixtures.valid.capabilities
    )
    let stream = try await runtime.stream(request: fixtures.valid.request)
    let collector = Task {
        var events: [SaturnNodeInferenceEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    try await runtime.emitDelta("Local", requestID: fixtures.valid.request.requestID)
    try await runtime.emitDelta(" inference", requestID: fixtures.valid.request.requestID)
    try await runtime.emitUsage(
        inputTokens: 8,
        outputTokens: 4,
        requestID: fixtures.valid.request.requestID
    )
    try await runtime.complete(requestID: fixtures.valid.request.requestID)

    let events = try await collector.value
    var validator = SaturnNodeInferenceEventSequenceValidator()
    for event in events {
        try validator.accept(event)
    }

    #expect(events.map(\.type) == [.started, .delta, .delta, .usage, .completed])
    #expect(await runtime.activeRequests().isEmpty)
    #expect(await runtime.terminalRequests() == [fixtures.valid.request.requestID])
}

@Test("Cancellation is terminal, idempotent, and leaves no active work")
func fakeRuntimeCancellation() async throws {
    let fixtures = try contractFixtures()
    let runtime = DeterministicFakeInferenceRuntime(
        capabilities: fixtures.valid.capabilities
    )
    let request = try replacementRequest(
        from: fixtures.valid.request,
        requestID: try requestID("22222222-2222-4222-8222-222222222222"),
        requestNonce: try nonce("nonce_2222222222222222")
    )
    let stream = try await runtime.stream(request: request)
    let collector = Task {
        var events: [SaturnNodeInferenceEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    try await runtime.cancel(requestID: request.requestID)
    try await runtime.cancel(requestID: request.requestID)

    let events = try await collector.value
    var validator = SaturnNodeInferenceEventSequenceValidator()
    for event in events {
        try validator.accept(event)
    }

    #expect(events.map(\.type) == [.started, .cancelled])
    #expect(await runtime.activeRequests().isEmpty)
    #expect(await runtime.terminalRequests().contains(request.requestID))
}

@Test("Event sequence validator rejects events after terminal completion")
func eventSequenceRejectsSecondTerminal() throws {
    let id = try requestID("33333333-3333-4333-8333-333333333333")
    let node = try self.id("saturn-node-01")
    let model = try self.id("local-model")
    var validator = SaturnNodeInferenceEventSequenceValidator()

    try validator.accept(
        .started(requestID: id, sequence: 0, nodeID: node, modelID: model)
    )
    try validator.accept(
        .completed(requestID: id, sequence: 1, finishReason: .stop)
    )

    #expect(throws: SaturnNodeError.requestAlreadyTerminal) {
        try validator.accept(.cancelled(requestID: id, sequence: 2))
    }
}

@Test("Bootstrap runtime fails closed")
func unavailableRuntimeFailsClosed() async throws {
    let runtime = UnavailableInferenceRuntime()
    let fixtures = try contractFixtures()

    await #expect(throws: SaturnNodeError.runtimeUnavailable) {
        _ = try await runtime.capabilities()
    }
    await #expect(throws: SaturnNodeError.runtimeUnavailable) {
        _ = try await runtime.stream(request: fixtures.valid.request)
    }
    await #expect(throws: SaturnNodeError.runtimeUnavailable) {
        try await runtime.cancel(requestID: fixtures.valid.request.requestID)
    }
}
