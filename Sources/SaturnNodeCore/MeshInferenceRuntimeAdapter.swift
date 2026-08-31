import Foundation
import SaturnMLXMesh

/// Maps the mesh `MLXInferenceRuntime` surface onto `SaturnNodeInferenceRuntime`.
///
/// Runtime-agnostic: `SimulatedMLXInferenceRuntime` (CI) or
/// `MeshModelInferenceRuntime` (opt-in `--real-smoke`). Default composition
/// still uses `UnavailableInferenceRuntime`.
///
/// Owns sequence numbers, deadline admission, in-flight deadline cancel,
/// consumer-cancel propagation, and mesh→Saturn error mapping.
/// Does not open listeners, parse credentials, or download weights.
public actor MeshInferenceRuntimeAdapter: SaturnNodeInferenceRuntime {
    private let mesh: any MLXInferenceRuntime
    private let nodeID: SaturnNodeIdentifier
    private let serviceVersion: String
    private let acceptedCredentialEpoch: Int
    private let now: @Sendable () -> Date

    /// Next Saturn sequence number per active request. Mesh chunks have none.
    private var nextSequence: [RequestIdentifier: Int] = [:]

    public init(
        mesh: any MLXInferenceRuntime,
        nodeID: SaturnNodeIdentifier,
        serviceVersion: String,
        acceptedCredentialEpoch: Int = 0,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.mesh = mesh
        self.nodeID = nodeID
        self.serviceVersion = serviceVersion
        self.acceptedCredentialEpoch = max(0, acceptedCredentialEpoch)
        self.now = now
    }

    public func capabilities() async throws -> SaturnNodeRuntimeCapabilities {
        let meshCaps = try await mesh.capabilities()
        var models: [SaturnNodeModelCapability] = []
        models.reserveCapacity(meshCaps.models.count)
        for model in meshCaps.models {
            guard let modelID = ModelIdentifier(rawValue: model.modelID) else {
                throw SaturnNodeError.invalidRuntimeCapabilities
            }
            models.append(
                try SaturnNodeModelCapability(
                    modelID: modelID,
                    maximumContextTokens: model.maxContextTokens,
                    maximumOutputTokens: model.maxOutputTokens
                )
            )
        }

        return try SaturnNodeRuntimeCapabilities(
            nodeID: nodeID,
            serviceVersion: serviceVersion,
            state: MeshRuntimeMapping.mapState(meshCaps.state),
            models: models,
            maximumConcurrentRequests: meshCaps.maximumConcurrentRequests,
            acceptedCredentialEpoch: acceptedCredentialEpoch
        )
    }

    public func stream(
        request: SaturnNodeInferenceRequest
    ) async throws -> AsyncThrowingStream<SaturnNodeInferenceEvent, Error> {
        let deadline = request.deadlineAt
        try MeshRuntimeMapping.requireFreshDeadline(deadline, now: now())

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

                let watchdog = Task { [mesh = self.mesh] in
                    let remaining = deadline.timeIntervalSinceNow
                    if remaining > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                    }
                    guard !Task.isCancelled else { return }
                    await mesh.cancel(requestID: meshRequestID)
                }

                var timedOut = false

                do {
                    for try await chunk in meshStream {
                        if Task.isCancelled { break }

                        let pastDeadline = self.now() >= deadline
                        if pastDeadline {
                            timedOut = true
                            if case .cancelled = chunk { break }
                            await self.mesh.cancel(requestID: meshRequestID)
                            break
                        }

                        let event = try await self.mapChunk(chunk, for: request)
                        continuation.yield(event)
                        if event.isTerminal { break }
                    }

                    if timedOut {
                        continuation.finish(throwing: SaturnNodeError.requestTimedOut)
                    } else if !Task.isCancelled {
                        continuation.finish()
                    }
                } catch is CancellationError {
                    // Consumer cancellation owns outer-stream termination.
                } catch let error as MeshInferenceError {
                    continuation.finish(
                        throwing: MeshRuntimeMapping.finishError(
                            timedOut: timedOut,
                            deadline: deadline,
                            now: self.now(),
                            otherwise: MeshRuntimeMapping.mapError(error)
                        )
                    )
                } catch {
                    continuation.finish(
                        throwing: MeshRuntimeMapping.finishError(
                            timedOut: timedOut,
                            deadline: deadline,
                            now: self.now(),
                            otherwise: .malformedRequest(error.localizedDescription)
                        )
                    )
                }

                watchdog.cancel()
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
        // Keep sequence state until the mesh cancellation terminal arrives.
        await mesh.cancel(requestID: InferenceRequestID(requestID.rawValue))
    }

    private func mapChunk(
        _ chunk: InferenceChunk,
        for request: SaturnNodeInferenceRequest
    ) throws -> SaturnNodeInferenceEvent {
        let sequence = nextSequence[request.requestID] ?? 0
        nextSequence[request.requestID] = sequence + 1

        switch chunk {
        case let .started(meshRequestID):
            try requireMatchingRequestID(meshRequestID, expected: request.requestID, context: "started")
            return .started(
                requestID: request.requestID,
                sequence: sequence,
                nodeID: nodeID,
                modelID: request.modelID
            )

        case let .delta(meshRequestID, text, _):
            try requireMatchingRequestID(meshRequestID, expected: request.requestID, context: "delta")
            guard !text.isEmpty else {
                throw SaturnNodeError.malformedRequest("Mesh delta text must not be empty.")
            }
            return .delta(requestID: request.requestID, sequence: sequence, text: text)

        case let .completed(meshRequestID, finishReason):
            try requireMatchingRequestID(meshRequestID, expected: request.requestID, context: "completed")
            switch finishReason {
            case .stop:
                return .completed(requestID: request.requestID, sequence: sequence, finishReason: .stop)
            case .length:
                return .completed(requestID: request.requestID, sequence: sequence, finishReason: .length)
            case .cancelled:
                return .cancelled(requestID: request.requestID, sequence: sequence)
            }

        case let .cancelled(meshRequestID):
            try requireMatchingRequestID(meshRequestID, expected: request.requestID, context: "cancelled")
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
}
