import Foundation
import Testing
import SaturnMLXMesh
@testable import SaturnNodeCore

private func makeAcceptanceRequest(
    kind: SaturnNodeHardwareAcceptanceRequestKind,
    modelID: ModelIdentifier
) throws -> SaturnNodeInferenceRequest {
    let nonceRaw = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    let maximumOutputTokens: Int
    switch kind {
    case .ordinary, .recovery:
        maximumOutputTokens = 8
    case .cancellation:
        maximumOutputTokens = 32
    }

    return try SaturnNodeInferenceRequest(
        requestID: RequestIdentifier(UUID()),
        requestNonce: try #require(RequestNonce(rawValue: nonceRaw)),
        deploymentID: try #require(DeploymentIdentifier(rawValue: "acceptance-test")),
        workloadID: try #require(WorkloadIdentifier(rawValue: "acceptance-test")),
        modelID: modelID,
        inputText: "deterministic acceptance prompt",
        maximumContextTokens: 2048,
        maximumOutputTokens: maximumOutputTokens,
        deadlineAt: Date().addingTimeInterval(30)
    )
}

@Test("Hardware acceptance arguments preserve legacy smoke defaults")
func hardwareAcceptanceArgumentDefaults() throws {
    let baseline = try SaturnNodeHardwareAcceptanceConfiguration(
        arguments: ["--real-smoke"]
    )
    #expect(baseline.requestCount == 1)
    #expect(baseline.cancellationCount == 0)

    let legacyCancellation = try SaturnNodeHardwareAcceptanceConfiguration(
        arguments: ["--real-smoke", "--cancel-recovery"]
    )
    #expect(legacyCancellation.requestCount == 1)
    #expect(legacyCancellation.cancellationCount == 1)
}

@Test("Hardware acceptance arguments parse explicit sustained counts")
func hardwareAcceptanceArgumentCounts() throws {
    let configuration = try SaturnNodeHardwareAcceptanceConfiguration(
        arguments: [
            "--real-smoke",
            "--requests", "20",
            "--cancellations", "5"
        ]
    )

    #expect(configuration.requestCount == 20)
    #expect(configuration.cancellationCount == 5)
}

@Test("Explicit cancellation count overrides legacy cancel flag")
func explicitCancellationCountWins() throws {
    let configuration = try SaturnNodeHardwareAcceptanceConfiguration(
        arguments: [
            "--real-smoke",
            "--cancel-recovery",
            "--cancellations", "3"
        ]
    )

    #expect(configuration.cancellationCount == 3)
}

@Test("Hardware acceptance rejects invalid sustained counts")
func hardwareAcceptanceRejectsInvalidCounts() {
    #expect(throws: SaturnNodeHardwareAcceptanceError.invalidRequestCount(0)) {
        _ = try SaturnNodeHardwareAcceptanceConfiguration(
            requestCount: 0,
            cancellationCount: 0
        )
    }

    #expect(throws: SaturnNodeHardwareAcceptanceError.invalidCancellationCount(-1)) {
        _ = try SaturnNodeHardwareAcceptanceConfiguration(
            requestCount: 1,
            cancellationCount: -1
        )
    }

    #expect(throws: SaturnNodeHardwareAcceptanceError.missingArgumentValue("--requests")) {
        _ = try SaturnNodeHardwareAcceptanceConfiguration(
            arguments: ["--real-smoke", "--requests"]
        )
    }
}

@Test("Timing summary reports nearest-rank p95 and true median")
func hardwareAcceptanceTimingSummary() throws {
    let odd = try SaturnNodeHardwareAcceptanceTimingSummary(
        samples: [
            .milliseconds(10),
            .milliseconds(20),
            .milliseconds(30),
            .milliseconds(40),
            .milliseconds(50)
        ]
    )
    #expect(odd.minimumMilliseconds == 10)
    #expect(odd.medianMilliseconds == 30)
    #expect(odd.p95Milliseconds == 50)

    let even = try SaturnNodeHardwareAcceptanceTimingSummary(
        samples: [
            .milliseconds(10),
            .milliseconds(20),
            .milliseconds(30),
            .milliseconds(40)
        ]
    )
    #expect(even.medianMilliseconds == 25)
}

@Test("Sustained runner reuses one runtime for ordinary and cancel-recovery cycles")
func sustainedAcceptanceRunner() async throws {
    let mesh = SimulatedMLXInferenceRuntime(
        config: SimulatedInferenceConfig(
            modelID: "sim-model",
            maxContextTokens: 4096,
            maxOutputTokens: 64,
            maximumConcurrentRequests: 1,
            chunkCount: 20,
            chunkDelayNanoseconds: 1_000_000
        )
    )
    let modelID = try #require(ModelIdentifier(rawValue: "sim-model"))
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: mesh,
        nodeID: try #require(SaturnNodeIdentifier(rawValue: "saturn-node-acceptance-test")),
        serviceVersion: "0.0.0-acceptance-test"
    )
    let runner = SaturnNodeHardwareAcceptanceRunner(
        runtime: adapter,
        configuration: try SaturnNodeHardwareAcceptanceConfiguration(
            requestCount: 3,
            cancellationCount: 2
        ),
        makeRequest: { kind in
            try makeAcceptanceRequest(kind: kind, modelID: modelID)
        },
        isQuiescent: {
            await mesh.activeRequestIDs().isEmpty
        }
    )

    let report = try await runner.run()

    #expect(report.ordinarySamples.count == 3)
    #expect(report.cancellationSamples.count == 2)
    #expect(report.recoverySamples.count == 2)
    #expect(report.ordinarySamples.allSatisfy { $0.deltaCount > 0 })
    #expect(report.recoverySamples.allSatisfy { $0.deltaCount > 0 })
    #expect(report.cancellationSamples.allSatisfy { $0.deltaCountBeforeCancellation > 0 })
    #expect(await mesh.activeRequestIDs().isEmpty)

    let telemetry = await mesh.telemetrySnapshot()
    #expect(telemetry.count == 7)
}

@Test("Sustained runner fails closed when runtime is not quiescent")
func sustainedAcceptanceRequiresQuiescence() async throws {
    let mesh = SimulatedMLXInferenceRuntime(
        config: SimulatedInferenceConfig(
            modelID: "sim-model",
            chunkCount: 2,
            chunkDelayNanoseconds: 0
        )
    )
    let modelID = try #require(ModelIdentifier(rawValue: "sim-model"))
    let adapter = MeshInferenceRuntimeAdapter(
        mesh: mesh,
        nodeID: try #require(SaturnNodeIdentifier(rawValue: "saturn-node-quiescence-test")),
        serviceVersion: "0.0.0-quiescence-test"
    )
    let runner = SaturnNodeHardwareAcceptanceRunner(
        runtime: adapter,
        configuration: try SaturnNodeHardwareAcceptanceConfiguration(
            requestCount: 1,
            cancellationCount: 0
        ),
        makeRequest: { kind in
            try makeAcceptanceRequest(kind: kind, modelID: modelID)
        },
        isQuiescent: { false }
    )

    await #expect(throws: SaturnNodeHardwareAcceptanceError.runtimeNotQuiescent) {
        _ = try await runner.run()
    }
}
