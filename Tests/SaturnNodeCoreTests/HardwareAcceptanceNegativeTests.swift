import Foundation
import Testing
@testable import SaturnNodeCore

private enum ScriptedAcceptanceBehavior: Sendable {
    case unexpectedCancellation
    case missingCompletion
    case sequenceViolation
}

private struct ScriptedAcceptanceRuntime: SaturnNodeInferenceRuntime {
    let behavior: ScriptedAcceptanceBehavior

    func capabilities() async throws -> SaturnNodeRuntimeCapabilities {
        throw SaturnNodeError.runtimeUnavailable
    }

    func stream(
        request: SaturnNodeInferenceRequest
    ) async throws -> AsyncThrowingStream<SaturnNodeInferenceEvent, Error> {
        guard let nodeID = SaturnNodeIdentifier(rawValue: "saturn-node-negative-test") else {
            throw SaturnNodeError.invalidRuntimeCapabilities
        }

        let pair = AsyncThrowingStream<SaturnNodeInferenceEvent, Error>.makeStream()
        pair.continuation.yield(
            .started(
                requestID: request.requestID,
                sequence: 0,
                nodeID: nodeID,
                modelID: request.modelID
            )
        )

        switch behavior {
        case .unexpectedCancellation:
            pair.continuation.yield(
                .cancelled(requestID: request.requestID, sequence: 1)
            )

        case .missingCompletion:
            pair.continuation.yield(
                .delta(requestID: request.requestID, sequence: 1, text: "tok")
            )

        case .sequenceViolation:
            pair.continuation.yield(
                .delta(requestID: request.requestID, sequence: 2, text: "tok")
            )
        }

        pair.continuation.finish()
        return pair.stream
    }

    func cancel(requestID: RequestIdentifier) async throws {}
}

private func makeNegativeAcceptanceRequest() throws -> SaturnNodeInferenceRequest {
    let nonceRaw = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    return try SaturnNodeInferenceRequest(
        requestID: RequestIdentifier(UUID()),
        requestNonce: try #require(RequestNonce(rawValue: nonceRaw)),
        deploymentID: try #require(DeploymentIdentifier(rawValue: "negative-test")),
        workloadID: try #require(WorkloadIdentifier(rawValue: "negative-test")),
        modelID: try #require(ModelIdentifier(rawValue: "sim-model")),
        inputText: "deterministic negative-path prompt",
        maximumContextTokens: 2048,
        maximumOutputTokens: 8,
        deadlineAt: Date().addingTimeInterval(30)
    )
}

private func makeNegativeRunner(
    behavior: ScriptedAcceptanceBehavior
) throws -> SaturnNodeHardwareAcceptanceRunner {
    SaturnNodeHardwareAcceptanceRunner(
        runtime: ScriptedAcceptanceRuntime(behavior: behavior),
        configuration: try SaturnNodeHardwareAcceptanceConfiguration(
            requestCount: 1,
            cancellationCount: 0
        ),
        makeRequest: { _ in
            try makeNegativeAcceptanceRequest()
        },
        isQuiescent: { true }
    )
}

@Test("Sustained runner rejects an unexpected cancellation terminal")
func sustainedRunnerRejectsUnexpectedCancellation() async throws {
    let runner = try makeNegativeRunner(behavior: .unexpectedCancellation)

    await #expect(throws: SaturnNodeHardwareAcceptanceError.unexpectedCancellation) {
        _ = try await runner.run()
    }
}

@Test("Sustained runner rejects a stream without completion")
func sustainedRunnerRejectsMissingCompletion() async throws {
    let runner = try makeNegativeRunner(behavior: .missingCompletion)

    await #expect(throws: SaturnNodeHardwareAcceptanceError.missingCompletion) {
        _ = try await runner.run()
    }
}

@Test("Sustained runner propagates sequence validation failures")
func sustainedRunnerRejectsSequenceViolation() async throws {
    let runner = try makeNegativeRunner(behavior: .sequenceViolation)

    await #expect(
        throws: SaturnNodeError.malformedRequest(
            "Inference event sequence is not contiguous."
        )
    ) {
        _ = try await runner.run()
    }
}

@Test("Acceptance failure diagnostic codes remain metadata-only")
func acceptanceFailureDiagnosticCodes() {
    #expect(
        SaturnNodeHardwareAcceptanceError.runtimeNotQuiescent.diagnosticCode
            == "runtime_not_quiescent"
    )
    #expect(
        SaturnNodeHardwareAcceptanceError.invalidArgumentValue(
            "--requests",
            "sensitive-looking-value"
        ).diagnosticCode == "invalid_argument_value"
    )
}
