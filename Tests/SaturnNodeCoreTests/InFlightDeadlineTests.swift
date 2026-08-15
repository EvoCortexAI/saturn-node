import Foundation
import Testing
import SaturnMLXMesh
@testable import SaturnNodeCore

private func makeNodeID(_ value: String = "saturn-node-deadline-01") throws -> SaturnNodeIdentifier {
    try #require(SaturnNodeIdentifier(rawValue: value))
}

private func makeRequestID(
    _ value: String = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
) throws -> RequestIdentifier {
    try #require(RequestIdentifier(rawValue: value))
}

private func makeRequest(
    requestID: RequestIdentifier? = nil,
    maxOutput: Int = 32,
    deadlineAt: Date
) throws -> SaturnNodeInferenceRequest {
    try SaturnNodeInferenceRequest(
        requestID: requestID ?? makeRequestID(),
        requestNonce: try #require(RequestNonce(rawValue: "nonce_deadline_test_01")),
        deploymentID: try #require(DeploymentIdentifier(rawValue: "deploy-deadline-01")),
        workloadID: try #require(WorkloadIdentifier(rawValue: "workload-deadline-01")),
        modelID: try #require(ModelIdentifier(rawValue: "sim-model")),
        inputText: "deadline prompt",
        maximumContextTokens: 2048,
        maximumOutputTokens: maxOutput,
        deadlineAt: deadlineAt
    )
}

@Test("In-flight deadline expires during generation and maps to requestTimedOut")
func inFlightDeadlineTimesOut() async throws {
    let mesh = SimulatedMLXInferenceRuntime(
        config: SimulatedInferenceConfig(
            modelID: "sim-model",
            chunkCount: 40,
            chunkDelayNanoseconds: 40_000_000
        )
    )
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: mesh,
        nodeID: try makeNodeID(),
        serviceVersion: "0.0.0-deadline"
    )
    let request = try makeRequest(
        maxOutput: 40,
        deadlineAt: Date().addingTimeInterval(0.12)
    )

    let stream = try await adapter.stream(request: request)
    await #expect(throws: SaturnNodeError.requestTimedOut) {
        for try await _ in stream {}
    }

    #expect(await mesh.activeRequestIDs().isEmpty)
}

@Test("Subsequent request succeeds after in-flight deadline timeout")
func subsequentRequestAfterInFlightTimeout() async throws {
    let mesh = SimulatedMLXInferenceRuntime(
        config: SimulatedInferenceConfig(
            modelID: "sim-model",
            chunkCount: 40,
            chunkDelayNanoseconds: 40_000_000
        )
    )
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: mesh,
        nodeID: try makeNodeID(),
        serviceVersion: "0.0.0-deadline"
    )

    let first = try makeRequest(
        requestID: try makeRequestID("dddddddd-dddd-4ddd-8ddd-dddddddddddd"),
        maxOutput: 40,
        deadlineAt: Date().addingTimeInterval(0.12)
    )
    let firstStream = try await adapter.stream(request: first)
    await #expect(throws: SaturnNodeError.requestTimedOut) {
        for try await _ in firstStream {}
    }
    #expect(await mesh.activeRequestIDs().isEmpty)

    let second = try makeRequest(
        requestID: try makeRequestID("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"),
        maxOutput: 4,
        deadlineAt: Date().addingTimeInterval(30)
    )
    let secondStream = try await adapter.stream(request: second)
    var events: [SaturnNodeInferenceEvent] = []
    for try await event in secondStream {
        events.append(event)
    }

    #expect(events.first?.type == .started)
    #expect(events.last?.isTerminal == true)
    #expect(await mesh.activeRequestIDs().isEmpty)
}

@Test("Explicit cancel before deadline still yields cancelled terminal")
func explicitCancelBeforeDeadlineRemainsCancelled() async throws {
    let mesh = SimulatedMLXInferenceRuntime(
        config: SimulatedInferenceConfig(
            modelID: "sim-model",
            chunkCount: 30,
            chunkDelayNanoseconds: 20_000_000
        )
    )
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: mesh,
        nodeID: try makeNodeID(),
        serviceVersion: "0.0.0-deadline"
    )
    let request = try makeRequest(
        maxOutput: 30,
        deadlineAt: Date().addingTimeInterval(30)
    )

    let stream = try await adapter.stream(request: request)
    var events: [SaturnNodeInferenceEvent] = []
    var cancelled = false
    for try await event in stream {
        events.append(event)
        if event.type == .delta, !cancelled {
            cancelled = true
            try await adapter.cancel(requestID: request.requestID)
        }
    }

    #expect(cancelled)
    #expect(events.last?.type == .cancelled)
    #expect(events.last?.isTerminal == true)
    #expect(await mesh.activeRequestIDs().isEmpty)
}

@Test("Long deadline still allows normal completion")
func longDeadlineAllowsCompletion() async throws {
    let mesh = SimulatedMLXInferenceRuntime(
        config: SimulatedInferenceConfig(
            modelID: "sim-model",
            chunkCount: 3,
            chunkDelayNanoseconds: 0
        )
    )
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: mesh,
        nodeID: try makeNodeID(),
        serviceVersion: "0.0.0-deadline"
    )
    let request = try makeRequest(
        maxOutput: 8,
        deadlineAt: Date().addingTimeInterval(60)
    )

    let stream = try await adapter.stream(request: request)
    var events: [SaturnNodeInferenceEvent] = []
    for try await event in stream {
        events.append(event)
    }

    #expect(events.first?.type == .started)
    #expect(events.last?.isTerminal == true)
    if case let .completed(_, _, reason) = events.last {
        #expect(reason == .stop || reason == .length)
    } else {
        Issue.record("Expected completed terminal, not cancel/timeout")
    }
}
