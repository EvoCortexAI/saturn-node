import Darwin
import Foundation
import SaturnMLXMesh
import SaturnNodeCore

@main
struct SaturnNodeBootstrap {
    private enum SmokeFailure: Error {
        case invalidIdentifiers
        case modelNotAdvertised
        case missingStarted
        case noGeneratedDeltas
        case missingCompletion
        case unexpectedCancellation
        case cancellationNotObserved
        case requestStillActive
    }

    private struct CompletionMetrics {
        let deltaCount: Int
        let timeToFirstDelta: Duration
        let generationDuration: Duration
        let finishReason: SaturnNodeInferenceFinishReason
    }

    static func main() async {
        let arguments = Set(CommandLine.arguments.dropFirst())

        if arguments.contains("--real-smoke") {
            let succeeded = await runRealSmoke(arguments: arguments)
            if !succeeded {
                exit(EXIT_FAILURE)
            }
            return
        }

        // Default: production composition is unavailable. No listener, no model load.
        do {
            _ = try SaturnNodeServiceComposition.unavailable()
        } catch {
            // Still fail closed; do not surface internal details.
        }

        FileHandle.standardError.write(
            Data(
                "saturn-node: no network listener or inference runtime configured (pass --real-smoke for explicit hardware acceptance)\n".utf8
            )
        )
    }

    /// Explicit opt-in real-hardware acceptance path.
    ///
    /// This loads real weights and sends requests through the Node adapter. It does
    /// not open a listener, select production composition, or authorize deployment.
    private static func runRealSmoke(arguments: Set<String>) async -> Bool {
        let showContent = arguments.contains("--show-content")
        let runCancellationRecovery = arguments.contains("--cancel-recovery")
        let modelIDRaw = AcceptanceModelPin.primaryModelID
        let clock = ContinuousClock()

        print("=== saturn-node real-runtime hardware acceptance ===")
        print("model_id=\(modelIDRaw)")
        print("content_output=\(showContent ? "enabled" : "suppressed")")
        print("cancel_recovery=\(runCancellationRecovery ? "enabled" : "disabled")")

        do {
            let loadStarted = clock.now
            let meshRuntime = try await MeshModelInferenceRuntime.loadPrimary()
            let loadDuration = loadStarted.duration(to: clock.now)

            guard let nodeID = SaturnNodeIdentifier(rawValue: "saturn-node-local-smoke"),
                  let modelID = ModelIdentifier(rawValue: modelIDRaw) else {
                throw SmokeFailure.invalidIdentifiers
            }

            let adapter = MeshInferenceRuntimeAdapter(
                mesh: meshRuntime,
                nodeID: nodeID,
                serviceVersion: "0.0.0-real-smoke",
                acceptedCredentialEpoch: 0
            )

            let capabilities = try await adapter.capabilities()
            guard capabilities.modelIDs.contains(modelID) else {
                throw SmokeFailure.modelNotAdvertised
            }

            print("node_id=\(nodeID.rawValue)")
            print("model_load_ms=\(milliseconds(loadDuration))")
            print("runtime_state=\(capabilities.state.rawValue)")
            print("maximum_concurrent_requests=\(capabilities.maximumConcurrentRequests)")

            let baseline = try await runCompletion(
                adapter: adapter,
                modelID: modelID,
                requestID: RequestIdentifier(UUID()),
                showContent: showContent
            )

            print("baseline_result=pass")
            print("baseline_delta_count=\(baseline.deltaCount)")
            print("baseline_ttfd_ms=\(milliseconds(baseline.timeToFirstDelta))")
            print("baseline_generation_ms=\(milliseconds(baseline.generationDuration))")
            print("baseline_finish_reason=\(baseline.finishReason.rawValue)")

            if runCancellationRecovery {
                try await runCancellationProbe(
                    adapter: adapter,
                    meshRuntime: meshRuntime,
                    modelID: modelID,
                    showContent: showContent
                )

                let recovery = try await runCompletion(
                    adapter: adapter,
                    modelID: modelID,
                    requestID: RequestIdentifier(UUID()),
                    showContent: showContent
                )

                print("cancel_recovery_result=pass")
                print("recovery_delta_count=\(recovery.deltaCount)")
                print("recovery_ttfd_ms=\(milliseconds(recovery.timeToFirstDelta))")
                print("recovery_generation_ms=\(milliseconds(recovery.generationDuration))")
                print("recovery_finish_reason=\(recovery.finishReason.rawValue)")
            }

            let telemetry = await meshRuntime.telemetrySnapshot()
            print("mesh_telemetry_records=\(telemetry.count)")
            print("result=pass")
            return true
        } catch {
            // Keep standard acceptance output free of prompt, response, path,
            // credential, and potentially sensitive dependency error details.
            FileHandle.standardError.write(Data("result=fail\n".utf8))
            return false
        }
    }

    private static func runCompletion(
        adapter: MeshInferenceRuntimeAdapter,
        modelID: ModelIdentifier,
        requestID: RequestIdentifier,
        showContent: Bool
    ) async throws -> CompletionMetrics {
        let request = try makeRequest(
            requestID: requestID,
            modelID: modelID,
            maximumOutputTokens: AcceptanceModelPin.smokeMaxTokens
        )
        let stream = try await adapter.stream(request: request)

        let clock = ContinuousClock()
        let startedAt = clock.now
        var firstDeltaAt: ContinuousClock.Instant?
        var deltaCount = 0
        var sawStarted = false
        var finishReason: SaturnNodeInferenceFinishReason?
        var sequenceValidator = SaturnNodeInferenceEventSequenceValidator()

        for try await event in stream {
            try sequenceValidator.accept(event)

            switch event {
            case .started:
                sawStarted = true
            case let .delta(_, _, text):
                guard !text.isEmpty else { continue }
                if firstDeltaAt == nil {
                    firstDeltaAt = clock.now
                }
                deltaCount += 1
                if showContent {
                    print(text, terminator: "")
                    fflush(stdout)
                }
            case let .completed(_, _, reason):
                finishReason = reason
            case .cancelled:
                throw SmokeFailure.unexpectedCancellation
            case .usage:
                break
            }
        }

        if showContent {
            print("")
        }

        guard sawStarted else {
            throw SmokeFailure.missingStarted
        }
        guard deltaCount > 0, let firstDeltaAt else {
            throw SmokeFailure.noGeneratedDeltas
        }
        guard let finishReason else {
            throw SmokeFailure.missingCompletion
        }

        return CompletionMetrics(
            deltaCount: deltaCount,
            timeToFirstDelta: startedAt.duration(to: firstDeltaAt),
            generationDuration: startedAt.duration(to: clock.now),
            finishReason: finishReason
        )
    }

    private static func runCancellationProbe(
        adapter: MeshInferenceRuntimeAdapter,
        meshRuntime: MeshModelInferenceRuntime,
        modelID: ModelIdentifier,
        showContent: Bool
    ) async throws {
        let requestID = RequestIdentifier(UUID())
        let request = try makeRequest(
            requestID: requestID,
            modelID: modelID,
            maximumOutputTokens: max(AcceptanceModelPin.smokeMaxTokens, 64)
        )
        let stream = try await adapter.stream(request: request)

        var cancellationRequested = false
        var cancellationObserved = false
        var sequenceValidator = SaturnNodeInferenceEventSequenceValidator()

        for try await event in stream {
            try sequenceValidator.accept(event)

            switch event {
            case let .delta(_, _, text):
                if showContent, !text.isEmpty {
                    print(text, terminator: "")
                    fflush(stdout)
                }
                if !cancellationRequested {
                    cancellationRequested = true
                    try await adapter.cancel(requestID: requestID)
                }
            case .cancelled:
                cancellationObserved = true
            case let .completed(_, _, reason):
                if reason == .cancelled {
                    cancellationObserved = true
                }
            case .started, .usage:
                break
            }
        }

        if showContent {
            print("")
        }

        guard cancellationRequested, cancellationObserved else {
            throw SmokeFailure.cancellationNotObserved
        }
        guard await meshRuntime.activeRequestIDs().isEmpty else {
            throw SmokeFailure.requestStillActive
        }

        print("cancel_result=pass")
    }

    private static func makeRequest(
        requestID: RequestIdentifier,
        modelID: ModelIdentifier,
        maximumOutputTokens: Int
    ) throws -> SaturnNodeInferenceRequest {
        let nonceRaw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        guard let nonce = RequestNonce(rawValue: nonceRaw),
              let deploymentID = DeploymentIdentifier(rawValue: "local-smoke"),
              let workloadID = WorkloadIdentifier(rawValue: "local-smoke") else {
            throw SmokeFailure.invalidIdentifiers
        }

        return try SaturnNodeInferenceRequest(
            requestID: requestID,
            requestNonce: nonce,
            deploymentID: deploymentID,
            workloadID: workloadID,
            modelID: modelID,
            inputText: AcceptanceModelPin.acceptancePrompt,
            maximumContextTokens: 8192,
            maximumOutputTokens: maximumOutputTokens,
            deadlineAt: Date().addingTimeInterval(120)
        )
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let components = duration.components
        let value = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return String(format: "%.3f", value)
    }
}
