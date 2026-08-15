import Darwin
import Foundation
import SaturnMLXMesh
import SaturnNodeCore

@main
struct SaturnNodeBootstrap {
    private enum SmokeFailure: Error {
        case invalidIdentifiers
        case modelNotAdvertised
    }

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

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
    /// This loads real weights once and sends all configured requests through the
    /// Node adapter in one process. It does not open a listener, select production
    /// composition, or authorize deployment.
    private static func runRealSmoke(arguments: [String]) async -> Bool {
        let showContent = arguments.contains("--show-content")
        let modelIDRaw = AcceptanceModelPin.primaryModelID
        let clock = ContinuousClock()

        print("=== saturn-node real-runtime hardware acceptance ===")
        print("model_id=\(modelIDRaw)")
        print("content_output=\(showContent ? "enabled" : "suppressed")")

        do {
            let configuration = try SaturnNodeHardwareAcceptanceConfiguration(
                arguments: arguments
            )
            print("requests=\(configuration.requestCount)")
            print("cancellations=\(configuration.cancellationCount)")
            print("cancel_recovery=\(configuration.cancellationCount > 0 ? "enabled" : "disabled")")

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
            print("model_load_count=1")
            print("runtime_state=\(capabilities.state.rawValue)")
            print("maximum_concurrent_requests=\(capabilities.maximumConcurrentRequests)")

            let observeDelta: SaturnNodeHardwareAcceptanceRunner.DeltaObserver
            if showContent {
                observeDelta = { text in
                    print("content_delta=\(text)")
                }
            } else {
                observeDelta = { _ in }
            }

            let runner = SaturnNodeHardwareAcceptanceRunner(
                runtime: adapter,
                configuration: configuration,
                makeRequest: { kind in
                    let maximumOutputTokens: Int
                    switch kind {
                    case .ordinary, .recovery:
                        maximumOutputTokens = AcceptanceModelPin.smokeMaxTokens
                    case .cancellation:
                        maximumOutputTokens = max(AcceptanceModelPin.smokeMaxTokens, 64)
                    }

                    return try Self.makeRequest(
                        requestID: RequestIdentifier(UUID()),
                        modelID: modelID,
                        maximumOutputTokens: maximumOutputTokens
                    )
                },
                isQuiescent: {
                    await meshRuntime.activeRequestIDs().isEmpty
                },
                observeDelta: observeDelta
            )

            let report = try await runner.run()

            if let baseline = report.ordinarySamples.first {
                print("baseline_result=pass")
                print("baseline_delta_count=\(baseline.deltaCount)")
                print("baseline_ttfd_ms=\(milliseconds(baseline.timeToFirstDelta))")
                print("baseline_generation_ms=\(milliseconds(baseline.generationDuration))")
                print("baseline_finish_reason=\(baseline.finishReason.rawValue)")
            }

            for (offset, sample) in report.ordinarySamples.enumerated() {
                let index = offset + 1
                print("ordinary_\(index)_result=pass")
                print("ordinary_\(index)_phase=\(index == 1 ? "first_after_model_load" : "same_process")")
                printCompletionSample(prefix: "ordinary_\(index)", sample: sample)
            }

            print("ordinary_requests_passed=\(report.ordinarySamples.count)/\(configuration.requestCount)")
            try printTimingSummary(
                prefix: "ordinary_ttfd",
                samples: report.ordinarySamples.map(\.timeToFirstDelta)
            )
            try printTimingSummary(
                prefix: "ordinary_generation",
                samples: report.ordinarySamples.map(\.generationDuration)
            )

            if configuration.cancellationCount > 0 {
                print("cancel_result=pass")

                for (offset, sample) in report.cancellationSamples.enumerated() {
                    let index = offset + 1
                    print("cancel_\(index)_result=pass")
                    print("cancel_\(index)_delta_count=\(sample.deltaCountBeforeCancellation)")
                    print("cancel_\(index)_terminal_ms=\(milliseconds(sample.cancellationDuration))")
                }

                for (offset, sample) in report.recoverySamples.enumerated() {
                    let index = offset + 1
                    print("recovery_\(index)_result=pass")
                    printCompletionSample(prefix: "recovery_\(index)", sample: sample)
                }

                print("cancellations_passed=\(report.cancellationSamples.count)/\(configuration.cancellationCount)")
                print("recoveries_passed=\(report.recoverySamples.count)/\(configuration.cancellationCount)")

                if let recovery = report.recoverySamples.first {
                    print("cancel_recovery_result=pass")
                    print("recovery_delta_count=\(recovery.deltaCount)")
                    print("recovery_ttfd_ms=\(milliseconds(recovery.timeToFirstDelta))")
                    print("recovery_generation_ms=\(milliseconds(recovery.generationDuration))")
                    print("recovery_finish_reason=\(recovery.finishReason.rawValue)")
                }

                try printTimingSummary(
                    prefix: "recovery_ttfd",
                    samples: report.recoverySamples.map(\.timeToFirstDelta)
                )
                try printTimingSummary(
                    prefix: "recovery_generation",
                    samples: report.recoverySamples.map(\.generationDuration)
                )
            }

            let telemetry = await meshRuntime.telemetrySnapshot()
            print("mesh_telemetry_records=\(telemetry.count)")
            print("sequence_violations=0")
            print("quiescence_checks=pass")
            print("active_requests_remaining=0")
            print("result=pass")
            return true
        } catch {
            // Keep standard acceptance output free of prompt, response, path,
            // credential, and potentially sensitive dependency error details.
            let failureReason = failureDiagnosticCode(for: error)
            FileHandle.standardError.write(
                Data("failure_reason=\(failureReason)\nresult=fail\n".utf8)
            )
            return false
        }
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

    private static func printCompletionSample(
        prefix: String,
        sample: SaturnNodeHardwareAcceptanceCompletionSample
    ) {
        print("\(prefix)_delta_count=\(sample.deltaCount)")
        print("\(prefix)_ttfd_ms=\(milliseconds(sample.timeToFirstDelta))")
        print("\(prefix)_generation_ms=\(milliseconds(sample.generationDuration))")
        print("\(prefix)_finish_reason=\(sample.finishReason.rawValue)")
    }

    private static func printTimingSummary(
        prefix: String,
        samples: [Duration]
    ) throws {
        let summary = try SaturnNodeHardwareAcceptanceTimingSummary(samples: samples)
        print("\(prefix)_min_ms=\(formatMilliseconds(summary.minimumMilliseconds))")
        print("\(prefix)_median_ms=\(formatMilliseconds(summary.medianMilliseconds))")
        print("\(prefix)_p95_ms=\(formatMilliseconds(summary.p95Milliseconds))")
    }

    private static func failureDiagnosticCode(for error: Error) -> String {
        if let acceptanceError = error as? SaturnNodeHardwareAcceptanceError {
            return acceptanceError.diagnosticCode
        }
        if let nodeError = error as? SaturnNodeError {
            return "node_\(nodeError.problemCode.rawValue)"
        }
        if let smokeFailure = error as? SmokeFailure {
            switch smokeFailure {
            case .invalidIdentifiers:
                return "invalid_identifiers"
            case .modelNotAdvertised:
                return "model_not_advertised"
            }
        }
        return "runtime_error"
    }

    private static func milliseconds(_ duration: Duration) -> String {
        let components = duration.components
        let value = Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
        return formatMilliseconds(value)
    }

    private static func formatMilliseconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
