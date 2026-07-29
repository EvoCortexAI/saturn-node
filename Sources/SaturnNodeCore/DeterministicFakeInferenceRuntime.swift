import Foundation

/// A deterministic, manually driven runtime for contract and orchestration tests.
///
/// This type does not perform inference and must not be selected by production
/// composition. Tests explicitly drive deltas, usage, completion, and cancellation.
public actor DeterministicFakeInferenceRuntime: SaturnNodeInferenceRuntime {
    private struct Session {
        let request: SaturnNodeInferenceRequest
        let continuation: AsyncThrowingStream<SaturnNodeInferenceEvent, Error>.Continuation
        var nextSequence: Int
        var hasUsage: Bool
    }

    private let capabilitiesValue: SaturnNodeRuntimeCapabilities
    private var sessions: [RequestIdentifier: Session] = [:]
    private var terminalRequestIDs: Set<RequestIdentifier> = []

    public init(capabilities: SaturnNodeRuntimeCapabilities) {
        self.capabilitiesValue = capabilities
    }

    public func capabilities() async throws -> SaturnNodeRuntimeCapabilities {
        capabilitiesValue
    }

    public func stream(
        request: SaturnNodeInferenceRequest
    ) async throws -> AsyncThrowingStream<SaturnNodeInferenceEvent, Error> {
        guard capabilitiesValue.state != .unavailable else {
            throw SaturnNodeError.runtimeUnavailable
        }
        guard capabilitiesValue.state != .saturated,
              sessions.count < capabilitiesValue.maximumConcurrentRequests else {
            throw SaturnNodeError.nodeSaturated
        }
        guard !sessions.keys.contains(request.requestID),
              !terminalRequestIDs.contains(request.requestID) else {
            throw SaturnNodeError.replayedCredential
        }
        guard let model = capabilitiesValue.models.first(where: { $0.modelID == request.modelID }) else {
            throw SaturnNodeError.modelNotAllowed
        }
        guard request.maximumContextTokens <= model.maximumContextTokens,
              request.maximumOutputTokens <= model.maximumOutputTokens else {
            throw SaturnNodeError.requestExceedsCredentialLimits
        }

        let pair = AsyncThrowingStream<SaturnNodeInferenceEvent, Error>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        var session = Session(
            request: request,
            continuation: pair.continuation,
            nextSequence: 1,
            hasUsage: false
        )
        pair.continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task {
                await self.consumerTerminated(requestID: request.requestID)
            }
        }

        pair.continuation.yield(
            .started(
                requestID: request.requestID,
                sequence: 0,
                nodeID: capabilitiesValue.nodeID,
                modelID: request.modelID
            )
        )
        sessions[request.requestID] = session
        return pair.stream
    }

    public func emitDelta(
        _ text: String,
        requestID: RequestIdentifier
    ) throws {
        guard !text.isEmpty else {
            throw SaturnNodeError.malformedRequest("A delta must not be empty.")
        }
        var session = try activeSession(requestID: requestID)
        session.continuation.yield(
            .delta(
                requestID: requestID,
                sequence: session.nextSequence,
                text: text
            )
        )
        session.nextSequence += 1
        sessions[requestID] = session
    }

    public func emitUsage(
        inputTokens: Int,
        outputTokens: Int,
        requestID: RequestIdentifier
    ) throws {
        guard inputTokens >= 0, outputTokens >= 0 else {
            throw SaturnNodeError.malformedRequest("Usage token counts must be non-negative.")
        }
        var session = try activeSession(requestID: requestID)
        guard !session.hasUsage else {
            throw SaturnNodeError.malformedRequest("Usage may be emitted only once.")
        }
        session.continuation.yield(
            .usage(
                requestID: requestID,
                sequence: session.nextSequence,
                inputTokens: inputTokens,
                outputTokens: outputTokens
            )
        )
        session.nextSequence += 1
        session.hasUsage = true
        sessions[requestID] = session
    }

    public func complete(
        requestID: RequestIdentifier,
        finishReason: SaturnNodeInferenceFinishReason = .stop
    ) throws {
        guard finishReason != .cancelled else {
            throw SaturnNodeError.malformedRequest("Use cancel for a cancelled terminal state.")
        }
        let session = try activeSession(requestID: requestID)
        session.continuation.yield(
            .completed(
                requestID: requestID,
                sequence: session.nextSequence,
                finishReason: finishReason
            )
        )
        session.continuation.finish()
        sessions.removeValue(forKey: requestID)
        terminalRequestIDs.insert(requestID)
    }

    public func fail(
        requestID: RequestIdentifier,
        error: SaturnNodeError
    ) throws {
        let session = try activeSession(requestID: requestID)
        session.continuation.finish(throwing: error)
        sessions.removeValue(forKey: requestID)
        terminalRequestIDs.insert(requestID)
    }

    public func cancel(requestID: RequestIdentifier) async throws {
        if terminalRequestIDs.contains(requestID) {
            return
        }
        guard let session = sessions[requestID] else {
            throw SaturnNodeError.unauthorized
        }
        session.continuation.yield(
            .cancelled(
                requestID: requestID,
                sequence: session.nextSequence
            )
        )
        session.continuation.finish()
        sessions.removeValue(forKey: requestID)
        terminalRequestIDs.insert(requestID)
    }

    public func activeRequests() -> Set<RequestIdentifier> {
        Set(sessions.keys)
    }

    public func terminalRequests() -> Set<RequestIdentifier> {
        terminalRequestIDs
    }

    private func activeSession(requestID: RequestIdentifier) throws -> Session {
        if terminalRequestIDs.contains(requestID) {
            throw SaturnNodeError.requestAlreadyTerminal
        }
        guard let session = sessions[requestID] else {
            throw SaturnNodeError.unauthorized
        }
        return session
    }

    private func consumerTerminated(requestID: RequestIdentifier) {
        guard sessions.removeValue(forKey: requestID) != nil else { return }
        terminalRequestIDs.insert(requestID)
    }
}
