import Foundation
import Testing
import SaturnMLXMesh
@testable import SaturnNodeCore

private func makeNodeID(_ value: String = "saturn-node-sim-01") throws -> SaturnNodeIdentifier {
    try #require(SaturnNodeIdentifier(rawValue: value))
}

private func makeRequestID(
    _ value: String = "11111111-1111-4111-8111-111111111111"
) throws -> RequestIdentifier {
    try #require(RequestIdentifier(rawValue: value))
}

private func makeModelID(_ value: String = "sim-model") throws -> ModelIdentifier {
    try #require(ModelIdentifier(rawValue: value))
}

private func makeRequest(
    requestID: RequestIdentifier? = nil,
    modelID: ModelIdentifier? = nil,
    maxOutput: Int = 8,
    deadlineAt: Date = Date().addingTimeInterval(30)
) throws -> SaturnNodeInferenceRequest {
    try SaturnNodeInferenceRequest(
        requestID: requestID ?? makeRequestID(),
        requestNonce: try #require(RequestNonce(rawValue: "nonce_sim_adapter_test_01")),
        deploymentID: try #require(DeploymentIdentifier(rawValue: "deploy-sim-01")),
        workloadID: try #require(WorkloadIdentifier(rawValue: "workload-sim-01")),
        modelID: modelID ?? makeModelID(),
        inputText: "sim prompt",
        maximumContextTokens: 2048,
        maximumOutputTokens: maxOutput,
        deadlineAt: deadlineAt
    )
}

private func expectContiguous(
    _ events: [SaturnNodeInferenceEvent],
    requestID: RequestIdentifier
) {
    for (index, event) in events.enumerated() {
        #expect(event.sequence == index)
        #expect(event.requestID == requestID)
    }
}

@Test("Adapter maps SimulatedMLX capabilities into Saturn capabilities")
func capabilitiesMapping() async throws {
    let nodeID = try makeNodeID()
    let mesh = SimulatedMLXInferenceRuntime(
        config: SimulatedInferenceConfig(
            modelID: "sim-model",
            maxContextTokens: 4096,
            maxOutputTokens: 256,
            maximumConcurrentRequests: 2
        )
    )
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: mesh,
        nodeID: nodeID,
        serviceVersion: "0.0.0-sim",
        acceptedCredentialEpoch: 3
    )

    let caps = try await adapter.capabilities()
    #expect(caps.nodeID == nodeID)
    #expect(caps.serviceVersion == "0.0.0-sim")
    #expect(caps.state == .available)
    #expect(caps.maximumConcurrentRequests == 2)
    #expect(caps.acceptedCredentialEpoch == 3)
    #expect(caps.models.count == 1)
    #expect(caps.models[0].modelID.rawValue == "sim-model")
    #expect(caps.models[0].maximumContextTokens == 4096)
    #expect(caps.models[0].maximumOutputTokens == 256)
}

@Test("Normal simulation stream yields contiguous started/delta/completed events")
func normalCompletionSequence() async throws {
    let nodeID = try makeNodeID()
    let mesh = SimulatedMLXInferenceRuntime(
        config: SimulatedInferenceConfig(
            modelID: "sim-model",
            chunkCount: 3,
            chunkDelayNanoseconds: 0
        )
    )
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: mesh,
        nodeID: nodeID,
        serviceVersion: "0.0.0-sim"
    )
    let request = try makeRequest(maxOutput: 8)

    let stream = try await adapter.stream(request: request)
    var events: [SaturnNodeInferenceEvent] = []
    for try await event in stream {
        events.append(event)
    }

    #expect(events.count >= 3)
    #expect(events.first?.type == .started)
    #expect(events.last?.isTerminal == true)
    if case let .completed(_, _, reason) = events.last {
        #expect(reason == .stop || reason == .length)
    } else {
        Issue.record("Expected terminal completed event")
    }
    expectContiguous(events, requestID: request.requestID)
}

@Test("Cancel preserves contiguous terminal sequence and permits a subsequent request")
func cancelThenSubsequentRequest() async throws {
    let nodeID = try makeNodeID()
    let mesh = SimulatedMLXInferenceRuntime(
        config: SimulatedInferenceConfig(
            modelID: "sim-model",
            chunkCount: 20,
            chunkDelayNanoseconds: 5_000_000
        )
    )
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: mesh,
        nodeID: nodeID,
        serviceVersion: "0.0.0-sim"
    )
    let first = try makeRequest(
        requestID: try makeRequestID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
        maxOutput: 32
    )

    let stream = try await adapter.stream(request: first)
    var firstEvents: [SaturnNodeInferenceEvent] = []
    var cancellationRequested = false

    for try await event in stream {
        firstEvents.append(event)
        if event.type == .delta, !cancellationRequested {
            cancellationRequested = true
            try await adapter.cancel(requestID: first.requestID)
        }
    }

    #expect(cancellationRequested)
    #expect(firstEvents.first?.type == .started)
    #expect(firstEvents.last?.type == .cancelled)
    #expect(firstEvents.last?.isTerminal == true)
    expectContiguous(firstEvents, requestID: first.requestID)

    let second = try makeRequest(
        requestID: try makeRequestID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"),
        maxOutput: 4
    )
    let secondStream = try await adapter.stream(request: second)
    var secondEvents: [SaturnNodeInferenceEvent] = []
    for try await event in secondStream {
        secondEvents.append(event)
    }

    #expect(secondEvents.first?.type == .started)
    #expect(secondEvents.last?.isTerminal == true)
    expectContiguous(secondEvents, requestID: second.requestID)
}

@Test("Already-expired request fails before mesh generation starts")
func expiredRequestFailsClosed() async throws {
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: SimulatedMLXInferenceRuntime(),
        nodeID: try makeNodeID(),
        serviceVersion: "0.0.0-sim"
    )
    let request = try makeRequest(deadlineAt: Date().addingTimeInterval(-1))

    await #expect(throws: SaturnNodeError.requestTimedOut) {
        _ = try await adapter.stream(request: request)
    }
}

@Test("Frozen clock admits only a future deadline")
func frozenClockDeadlineAdmission() async throws {
    let frozen = Date(timeIntervalSince1970: 1_700_000_000)
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: SimulatedMLXInferenceRuntime(),
        nodeID: try makeNodeID(),
        serviceVersion: "0.0.0-sim",
        now: { frozen }
    )

    await #expect(throws: SaturnNodeError.requestTimedOut) {
        _ = try await adapter.stream(request: try makeRequest(deadlineAt: frozen))
    }
    await #expect(throws: SaturnNodeError.requestTimedOut) {
        _ = try await adapter.stream(request: try makeRequest(deadlineAt: frozen.addingTimeInterval(-5)))
    }

    let live = try await adapter.stream(request: try makeRequest(deadlineAt: frozen.addingTimeInterval(30)))
    var events: [SaturnNodeInferenceEvent] = []
    for try await event in live {
        events.append(event)
    }
    #expect(events.first?.type == .started)
    #expect(events.last?.isTerminal == true)
}

@Test("Mesh timeout maps to requestTimedOut")
func runtimeTimeoutMapsToRequestTimedOut() async throws {
    let mesh = SimulatedMLXInferenceRuntime(
        config: SimulatedInferenceConfig(
            modelID: "sim-model",
            forceTimeout: true
        )
    )
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: mesh,
        nodeID: try makeNodeID(),
        serviceVersion: "0.0.0-sim"
    )
    let request = try makeRequest()
    let stream = try await adapter.stream(request: request)

    await #expect(throws: SaturnNodeError.requestTimedOut) {
        for try await _ in stream {}
    }
}

@Test("Capacity exhausted maps to nodeSaturated")
func capacityExhaustedMapsToNodeSaturated() async throws {
    let nodeID = try makeNodeID()
    let mesh = SimulatedMLXInferenceRuntime(
        config: SimulatedInferenceConfig(
            modelID: "sim-model",
            forceCapacityExhausted: true
        )
    )
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: mesh,
        nodeID: nodeID,
        serviceVersion: "0.0.0-sim"
    )
    let request = try makeRequest()

    let stream = try await adapter.stream(request: request)
    await #expect(throws: SaturnNodeError.nodeSaturated) {
        for try await _ in stream {}
    }
}

@Test("Unknown model maps to modelNotAllowed")
func unknownModelMapsToModelNotAllowed() async throws {
    let nodeID = try makeNodeID()
    let mesh = SimulatedMLXInferenceRuntime(
        config: SimulatedInferenceConfig(modelID: "sim-model")
    )
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: mesh,
        nodeID: nodeID,
        serviceVersion: "0.0.0-sim"
    )
    let otherModel = try makeModelID("other-model")
    let request = try makeRequest(modelID: otherModel)

    let stream = try await adapter.stream(request: request)
    await #expect(throws: SaturnNodeError.modelNotAllowed) {
        for try await _ in stream {}
    }
}

@Test("Unavailable production path is unchanged by the adapter")
func unavailableRuntimeStillFailsClosed() async throws {
    let runtime = UnavailableInferenceRuntime()
    await #expect(throws: SaturnNodeError.runtimeUnavailable) {
        _ = try await runtime.capabilities()
    }
    let request = try makeRequest()
    await #expect(throws: SaturnNodeError.runtimeUnavailable) {
        _ = try await runtime.stream(request: request)
    }
}
