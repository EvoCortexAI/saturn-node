import Foundation
import SaturnMLXMesh

/// Maps the mesh `MLXInferenceRuntime` surface onto `SaturnNodeInferenceRuntime`.
///
/// Runtime-agnostic: works with `SimulatedMLXInferenceRuntime` (CI) or
/// `MeshModelInferenceRuntime` (real MLX). The adapter does not choose which.
///
/// Default service composition still uses `UnavailableInferenceRuntime`.
/// Opt-in hardware path: `swift run saturn-node --real-smoke`.
///
/// Responsibilities:
/// - map Saturn request / event types onto the mesh adapter contract
/// - synthesize contiguous sequence numbers required by Saturn
/// - preserve sequence state through cancellation until the terminal event
/// - reject already-expired requests before starting inference
/// - propagate consumer cancellation into the mesh runtime
/// - map mesh errors onto `SaturnNodeError`
/// - keep prompt and generated text out of any telemetry path it owns
///
/// It does **not**:
/// - open listeners or perform networking
/// - parse workload credentials or authority receipts
/// - own admission, allowlist, or revocation policy
/// - download weights (that is `MeshModelInferenceRuntime.loadPrimary`)
/// - yet enforce an in-flight wall-clock deadline after generation has started
public actor MeshInferenceRuntimeAdapter: SaturnNodeInferenceRuntime {
    private let mesh: any MLXInferenceRuntime
    private let nodeID: SaturnNodeIdentifier
    private let serviceVersion: String
    private let acceptedCredentialEpoch: Int

    /// Tracks the next sequence number for each active request so Saturn's
    /// contiguous-sequence invariant is preserved even though the mesh
    /// contract does not carry sequence numbers.
    private var nextSequence: [RequestIdentifier: Int] = [:]

    public init(
        mesh: any MLXInferenceRuntime,
        nodeID: SaturnNodeIdentifier,
        serviceVersion: String,
        acceptedCredentialEpoch: Int = 0
    ) {
        self.mesh = mesh
        self.nodeID = nodeID
        self.serviceVersion = serviceVersion
        self.acceptedCredentialEpoch = max(0, acceptedCredentialEpoch)
    }

    // MARK: - SaturnNodeInferenceRuntime

    public func capabilities() async throws -> SaturnNodeRuntimeCapabilities {
        let meshCaps = try await mesh.capabilities()
        let state: SaturnNodeRuntimeState
        switch meshCaps.state {
        case .available:
            state = .available
        case .saturated:
            state = .saturated
        case .unavailable:
            state = .unavailable
        }

        var models: [SaturnNodeModelCapability] = []
        for model in meshCaps.models {
            guard let modelID = ModelIdentifier(rawValue: model.modelID) else {
                throw SaturnNodeError.invalidRuntimeCapabilities
            }
            let capability = try SaturnNodeModelCapability(
                modelID: modelID,
                maximumContextTokens: model.maxContextTokens,
                maximumOutputTokens: model.maxOutputTokens
            )
            models.append(capability)
        }

        return try SaturnNodeRuntimeCapabilities(
            nodeID: nodeID,
            serviceVersion: serviceVersion,
            state: state,
            models: models,
            maximumConcurrentRequests: meshCaps.maximumConcurrentRequests,
            acceptedCredentialEpoch: acceptedCredentialEpoch
        )
    }

    public func stream(
        request: SaturnNodeInferenceRequest
    ) async throws -> AsyncThrowingStream<SaturnNodeInferenceEvent, Error> {
        guard request.deadlineAt > Date() else {
            throw SaturnNodeError.requestTimedOut
        }

        let meshRequestID = InferenceRequestID(request.requestID.rawValue)
        let meshRequest = ValidatedInferenceRequest(
            requestID: meshRequestID,
            modelID: request.modelID.rawValue,
            prompt: request.inputText,
            maxOutputTokens: request.maximumOutputTokens
        )

        let meshStream = mesh.generate(meshRequest)
        nextSequence[request.requestID] = 0

        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: SaturnNodeError.runtimeUnavailable)
                    return
                }

                do {
                    for try await chunk in meshStream {
                        let event = try await self.mapChunk(chunk, for: request)
                        continuation.yield(event)
                        if event.isTerminal {
                            break
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    // Consumer cancellation owns termination of the outer stream.
                } catch let error as MeshInferenceError {
                    continuation.finish(throwing: Self.mapError(error))
                } catch {
                    continuation.finish(
                        throwing: SaturnNodeError.malformedRequest(error.localizedDescription)
                    )
                }

                await self.clearSequence(for: request.requestID)
            }

            continuation.onTermination = { termination in
                guard case .cancelled = termination else { return }
                task.cancel()
                Task { [weak self] in
                    guard let self else { return }
                    await self.consumerTerminated(
                        requestID: request.requestID,
                        meshRequestID: meshRequestID
                    )
                }
            }
        }
    }

    public func cancel(requestID: RequestIdentifier) async throws {
        // Do not clear sequence state here. The mesh emits the cancellation
        // terminal asynchronously, and that terminal must remain contiguous.
        await mesh.cancel(requestID: InferenceRequestID(requestID.rawValue))
    }

    // MARK: - Mapping

    private func mapChunk(
        _ chunk: InferenceChunk,
        for request: SaturnNodeInferenceRequest
    ) throws -> SaturnNodeInferenceEvent {
        let sequence = nextSequence[request.requestID] ?? 0
        nextSequence[request.requestID] = sequence + 1

        switch chunk {
        case let .started(meshRequestID):
            try requireMatchingRequestID(
                meshRequestID,
                expected: request.requestID,
                context: "started"
            )
            return .started(
                requestID: request.requestID,
                sequence: sequence,
                nodeID: nodeID,
                modelID: request.modelID
            )

        case let .delta(meshRequestID, text, _):
            try requireMatchingRequestID(
                meshRequestID,
                expected: request.requestID,
                context: "delta"
            )
            guard !text.isEmpty else {
                throw SaturnNodeError.malformedRequest("Mesh delta text must not be empty.")
            }
            return .delta(
                requestID: request.requestID,
                sequence: sequence,
                text: text
            )

        case let .completed(meshRequestID, finishReason):
            try requireMatchingRequestID(
                meshRequestID,
                expected: request.requestID,
                context: "completed"
            )
            switch finishReason {
            case .stop:
                return .completed(
                    requestID: request.requestID,
                    sequence: sequence,
                    finishReason: .stop
                )
            case .length:
                return .completed(
                    requestID: request.requestID,
                    sequence: sequence,
                    finishReason: .length
                )
            case .cancelled:
                return .cancelled(requestID: request.requestID, sequence: sequence)
            }

        case let .cancelled(meshRequestID):
            try requireMatchingRequestID(
                meshRequestID,
                expected: request.requestID,
                context: "cancelled"
            )
            return .cancelled(requestID: request.requestID, sequence: sequence)
        }
    }

    private func requireMatchingRequestID(
        _ meshRequestID: InferenceRequestID,
        expected: RequestIdentifier,
        context: String
    ) throws {
        guard meshRequestID.rawValue == expected.rawValue else {
            throw SaturnNodeError.malformedRequest("Mesh \(context) request ID mismatch.")
        }
    }

    private func consumerTerminated(
        requestID: RequestIdentifier,
        meshRequestID: InferenceRequestID
    ) async {
        await mesh.cancel(requestID: meshRequestID)
        clearSequence(for: requestID)
    }

    private func clearSequence(for requestID: RequestIdentifier) {
        nextSequence.removeValue(forKey: requestID)
    }

    private static func mapError(_ error: MeshInferenceError) -> SaturnNodeError {
        switch error {
        case .modelUnavailable:
            return .modelNotAllowed
        case .capacityExhausted:
            return .nodeSaturated
        case .requestTimeout:
            return .requestTimedOut
        case .cancelled:
            return .cancelled
        case .notLoaded:
            return .runtimeUnavailable
        case .generationFailed:
            return .malformedRequest("Mesh generation failed.")
        case .runtimeUnavailable:
            return .runtimeUnavailable
        }
    }
}
