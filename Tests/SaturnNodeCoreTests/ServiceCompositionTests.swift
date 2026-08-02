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

private struct StaticClaimsVerifier: WorkloadCredentialVerifying {
    let claims: WorkloadComputeClaims
    func verify(presentation: Data) async throws -> WorkloadComputeClaims {
        claims
    }
}

private func makeComposition(
    fixtures: ContractFixtures,
    verifier: any WorkloadCredentialVerifying? = nil,
    revocation: any RevocationStateProviding? = nil,
    replay: any ReplayProtectionProviding? = nil,
    allowlist: any ModelAllowlistProviding? = nil,
    admission: any AdmissionControlling? = nil,
    runtime: any SaturnNodeInferenceRuntime? = nil,
    lifecycle: any ServiceLifecycleControlling? = nil
) async throws -> SaturnNodeServiceComposition {
    let claims = fixtures.valid.claims
    let configuration = try SaturnNodeServiceConfiguration(
        nodeID: claims.nodeID,
        serviceVersion: "test-1",
        maximumConcurrentRequests: claims.maximumConcurrentRequests
    )
    let defaultAdmission = BoundedAdmissionController(maximum: claims.maximumConcurrentRequests)
    return SaturnNodeServiceComposition(
        configuration: configuration,
        identity: StaticNodeIdentity(nodeID: claims.nodeID),
        verifier: verifier ?? StaticClaimsVerifier(claims: claims),
        revocation: revocation ?? InMemoryRevocationState(epoch: claims.epoch),
        replay: replay ?? InMemoryReplayProtection(),
        allowlist: allowlist ?? StaticModelAllowlist(allowed: [claims.modelID]),
        admission: admission ?? defaultAdmission,
        runtime: runtime ?? DeterministicFakeInferenceRuntime(capabilities: fixtures.valid.capabilities),
        lifecycle: lifecycle ?? SimpleServiceLifecycle()
    )
}

@Test("Invalid configuration bounds fail closed")
func invalidConfigurationFailsClosed() throws {
    let node = try id("saturn-node-01")
    #expect(throws: SaturnNodeError.invalidServiceConfiguration("maximumConcurrentRequests")) {
        _ = try SaturnNodeServiceConfiguration(
            nodeID: node,
            serviceVersion: "1.0.0",
            maximumConcurrentRequests: 0
        )
    }
    #expect(throws: SaturnNodeError.invalidServiceConfiguration("serviceVersion")) {
        _ = try SaturnNodeServiceConfiguration(
            nodeID: node,
            serviceVersion: "",
            maximumConcurrentRequests: 1
        )
    }
}

@Test("Unavailable composition fails closed on every required seam")
func unavailableCompositionFailsClosed() async throws {
    let composition = try SaturnNodeServiceComposition.unavailable()
    let fixtures = try contractFixtures()

    await #expect(throws: SaturnNodeError.serviceDraining) {
        _ = try await composition.authorizeAndStream(
            presentation: Data(),
            request: fixtures.valid.request,
            now: fixtures.validationNow
        )
    }

    await #expect(throws: SaturnNodeError.identityUnavailable) {
        _ = try await composition.identity.currentNodeID()
    }
    await #expect(throws: SaturnNodeError.credentialVerificationUnavailable) {
        _ = try await composition.verifier.verify(presentation: Data())
    }
    await #expect(throws: SaturnNodeError.revocationStateUnavailable) {
        _ = try await composition.revocation.acceptedEpoch()
    }
    await #expect(throws: SaturnNodeError.replayProtectionUnavailable) {
        _ = try await composition.replay.hasSeen(
            requestID: fixtures.valid.request.requestID,
            nonce: fixtures.valid.request.requestNonce
        )
    }
    await #expect(throws: SaturnNodeError.modelAllowlistUnavailable) {
        _ = try await composition.allowlist.isAllowed(modelID: fixtures.valid.request.modelID)
    }
    await #expect(throws: SaturnNodeError.admissionUnavailable) {
        try await composition.admission.tryAdmit(requestID: fixtures.valid.request.requestID)
    }
    await #expect(throws: SaturnNodeError.runtimeUnavailable) {
        _ = try await composition.runtime.capabilities()
    }
}

@Test("Revoked credential is rejected before admission")
func revokedCredentialRejected() async throws {
    let fixtures = try contractFixtures()
    let claims = fixtures.valid.claims
    let revocation = InMemoryRevocationState(epoch: claims.epoch, revoked: [claims.credentialID])
    let admission = BoundedAdmissionController(maximum: 4)
    let composition = try await makeComposition(
        fixtures: fixtures,
        revocation: revocation,
        admission: admission
    )

    await #expect(throws: SaturnNodeError.revokedCredential) {
        _ = try await composition.authorizeAndStream(
            presentation: Data([0x01]),
            request: fixtures.valid.request,
            now: fixtures.validationNow
        )
    }
    #expect(await admission.activeCount() == 0)
}

@Test("Replayed request is rejected before admission")
func replayedRequestRejected() async throws {
    let fixtures = try contractFixtures()
    let replay = InMemoryReplayProtection()
    try await replay.record(
        requestID: fixtures.valid.request.requestID,
        nonce: fixtures.valid.request.requestNonce
    )
    let admission = BoundedAdmissionController(maximum: 4)
    let composition = try await makeComposition(
        fixtures: fixtures,
        replay: replay,
        admission: admission
    )

    await #expect(throws: SaturnNodeError.replayedCredential) {
        _ = try await composition.authorizeAndStream(
            presentation: Data([0x01]),
            request: fixtures.valid.request,
            now: fixtures.validationNow
        )
    }
    #expect(await admission.activeCount() == 0)
}

@Test("Non-allowlisted model never reaches runtime")
func nonAllowlistedModelRejected() async throws {
    let fixtures = try contractFixtures()
    let otherModel = try id("other-model")
    let admission = BoundedAdmissionController(maximum: 4)
    let composition = try await makeComposition(
        fixtures: fixtures,
        allowlist: StaticModelAllowlist(allowed: [otherModel]),
        admission: admission
    )

    await #expect(throws: SaturnNodeError.modelNotAllowed) {
        _ = try await composition.authorizeAndStream(
            presentation: Data([0x01]),
            request: fixtures.valid.request,
            now: fixtures.validationNow
        )
    }
    #expect(await admission.activeCount() == 0)
}

@Test("Drain mode rejects new work")
func drainRejectsNewWork() async throws {
    let fixtures = try contractFixtures()
    let lifecycle = SimpleServiceLifecycle()
    await lifecycle.beginDrain()
    let admission = BoundedAdmissionController(maximum: 4)
    let composition = try await makeComposition(
        fixtures: fixtures,
        admission: admission,
        lifecycle: lifecycle
    )

    await #expect(throws: SaturnNodeError.serviceDraining) {
        _ = try await composition.authorizeAndStream(
            presentation: Data([0x01]),
            request: fixtures.valid.request,
            now: fixtures.validationNow
        )
    }
    #expect(await admission.activeCount() == 0)
}

@Test("Admission saturation never begins inference")
func admissionSaturationBlocksRuntime() async throws {
    let fixtures = try contractFixtures()
    let admission = BoundedAdmissionController(maximum: 0)
    let composition = try await makeComposition(
        fixtures: fixtures,
        admission: admission
    )

    await #expect(throws: SaturnNodeError.nodeSaturated) {
        _ = try await composition.authorizeAndStream(
            presentation: Data([0x01]),
            request: fixtures.valid.request,
            now: fixtures.validationNow
        )
    }
}

@Test("Successful stream cleans up and permits a subsequent request")
func successfulStreamCleansUpForNextRequest() async throws {
    let fixtures = try contractFixtures()
    let runtime = DeterministicFakeInferenceRuntime(capabilities: fixtures.valid.capabilities)
    let admission = BoundedAdmissionController(maximum: 2)
    let composition = try await makeComposition(
        fixtures: fixtures,
        admission: admission,
        runtime: runtime
    )

    let firstStream = try await composition.authorizeAndStream(
        presentation: Data([0x01]),
        request: fixtures.valid.request,
        now: fixtures.validationNow
    )
    let collector = Task {
        var events: [SaturnNodeInferenceEvent] = []
        for try await event in firstStream {
            events.append(event)
        }
        return events
    }

    try await runtime.emitDelta("ok", requestID: fixtures.valid.request.requestID)
    try await runtime.complete(requestID: fixtures.valid.request.requestID)

    let events = try await collector.value
    #expect(events.last?.isTerminal == true)
    #expect(await admission.activeCount() == 0)

    // Second request with fresh identity must succeed after cleanup.
    let secondRequest = try SaturnNodeInferenceRequest(
        requestID: try requestID("44444444-4444-4444-8444-444444444444"),
        requestNonce: try nonce("nonce_second_request_01"),
        deploymentID: fixtures.valid.request.deploymentID,
        workloadID: fixtures.valid.request.workloadID,
        modelID: fixtures.valid.request.modelID,
        inputText: fixtures.valid.request.inputText,
        maximumContextTokens: fixtures.valid.request.maximumContextTokens,
        maximumOutputTokens: fixtures.valid.request.maximumOutputTokens,
        deadlineAt: fixtures.valid.request.deadlineAt
    )

    let secondStream = try await composition.authorizeAndStream(
        presentation: Data([0x02]),
        request: secondRequest,
        now: fixtures.validationNow
    )
    let secondCollector = Task {
        var events: [SaturnNodeInferenceEvent] = []
        for try await event in secondStream {
            events.append(event)
        }
        return events
    }
    try await runtime.cancel(requestID: secondRequest.requestID)
    let secondEvents = try await secondCollector.value
    #expect(secondEvents.map(\.type) == [.started, .cancelled])
    #expect(await admission.activeCount() == 0)
}

@Test("Wrong node identity fails closed")
func wrongNodeIdentityFailsClosed() async throws {
    let fixtures = try contractFixtures()
    let otherNode = try id("other-node")
    let configuration = try SaturnNodeServiceConfiguration(
        nodeID: fixtures.valid.claims.nodeID,
        serviceVersion: "test-1",
        maximumConcurrentRequests: 2
    )
    let composition = SaturnNodeServiceComposition(
        configuration: configuration,
        identity: StaticNodeIdentity(nodeID: otherNode),
        verifier: StaticClaimsVerifier(claims: fixtures.valid.claims),
        revocation: InMemoryRevocationState(epoch: fixtures.valid.claims.epoch),
        replay: InMemoryReplayProtection(),
        allowlist: StaticModelAllowlist(allowed: [fixtures.valid.claims.modelID]),
        admission: BoundedAdmissionController(maximum: 2),
        runtime: DeterministicFakeInferenceRuntime(capabilities: fixtures.valid.capabilities),
        lifecycle: SimpleServiceLifecycle()
    )

    await #expect(throws: SaturnNodeError.wrongNode) {
        _ = try await composition.authorizeAndStream(
            presentation: Data([0x01]),
            request: fixtures.valid.request,
            now: fixtures.validationNow
        )
    }
}
