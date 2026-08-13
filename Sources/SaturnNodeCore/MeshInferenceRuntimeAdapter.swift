import Foundation
import SaturnMLXMesh

/// Narrow, simulation-capable adapter from the stable `MLXInferenceRuntime`
/// surface in `saturn-mlx-mesh` onto `SaturnNodeInferenceRuntime`.
///
/// Production composition **must not** select this type until the real-hardware
/// gates (mesh#1 + G3 resource baseline) are green and Founder approval is
/// recorded. The ordinary executable path continues to use
/// `UnavailableInferenceRuntime`.
///
/// Responsibilities of this adapter:
/// - map Saturn request / event types onto the mesh adapter contract
/// - synthesize contiguous sequence numbers required by Saturn
/// - map mesh errors onto `SaturnNodeError`
/// - keep prompt and generated text out of any telemetry path it owns
///
/// It does **not**:
/// - open listeners or perform networking
/// - parse workload credentials or authority receipts
/// - load real models or touch Metal
/// - own admission, allowlist, or revocation policy
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
        for m in meshCaps.models {
            guard let modelID = ModelIdentifier(rawValue: m.modelID) else {
                throw SaturnNodeError.invalidRuntimeCapabilities
            }
            let capability = try SaturnNodeModelCapability(
                modelID: modelID,
                maximumContextTokens: m.maxContextTokens,
                maximumOutputTokens: m.maxOutputTokens
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
        let meshRequest = ValidatedInferenceRequest(
            requestID: InferenceRequestID(request.requestID.rawValue),
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
                } catch let error as MeshInferenceError {
                    continuation.finish(throwing: Self.mapError(error))
                } catch {
                    continuation.finish(throwing: SaturnNodeError.malformedRequest(error.localizedDescription))
                }
                await self.clearSequence(for: request.requestID)
            }
            continuation.onTermination = { _ in
                task.cancel()
                Task { await self.clearSequence(for: request.requestID) }
            }
        }
    }

    public func cancel(requestID: RequestIdentifier) async throws {
        await mesh.cancel(requestID: InferenceRequestID(requestID.rawValue))
        nextSequence.removeValue(forKey: requestID)
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
            guard meshRequestID.rawValue == request.requestID.rawValue else {
                throw SaturnNodeError.malformedRequest("Mesh started request ID mismatch.")
            }
            return .started(
                requestID: request.requestID,
                sequence: sequence,
                nodeID: nodeID,
                modelID: request.modelID
            )

        case let .delta(meshRequestID, text, _):
            guard meshRequestID.rawValue == request.requestID.rawValue else {
                throw SaturnNodeError.malformedRequest("Mesh delta request ID mismatch.")
            }
            guard !text.isEmpty else {
                throw SaturnNodeError.malformedRequest("Mesh delta text must not be empty.")
            }
            return .delta(
                requestID: request.requestID,
                sequence: sequence,
                text: text
            )

        case let .completed(meshRequestID, finishReason):
            guard meshRequestID.rawValue == request.requestID.rawValue else {
                throw SaturnNodeError.malformedRequest("Mesh completed request ID mismatch.")
            }
            let reason: SaturnNodeInferenceFinishReason
            switch finishReason {
            case .stop:
                reason = .stop
            case .length:
                reason = .length
            case .cancelled:
                // Mesh should not emit completed with cancelled; treat as cancel path.
                return .cancelled(requestID: request.requestID, sequence: sequence)
            }
            return .completed(
                requestID: request.requestID,
                sequence: sequence,
                finishReason: reason
            )

        case let .cancelled(meshRequestID):
            guard meshRequestID.rawValue == request.requestID.rawValue else {
                throw SaturnNodeError.malformedRequest("Mesh cancelled request ID mismatch.")
            }
            return .cancelled(requestID: request.requestID, sequence: sequence)
        }
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
