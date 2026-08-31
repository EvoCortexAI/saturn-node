import Foundation
import SaturnMLXMesh

/// Pure mapping between the mesh library contract and Saturn-Node errors/state.
/// Kept free of actors, streams, and clocks so CI can pin fail-closed tables.
enum MeshRuntimeMapping {
    static func requireFreshDeadline(_ deadline: Date, now: Date) throws {
        guard deadline > now else {
            throw SaturnNodeError.requestTimedOut
        }
    }

    static func mapState(_ state: InferenceRuntimeState) -> SaturnNodeRuntimeState {
        switch state {
        case .available:
            return .available
        case .saturated:
            return .saturated
        case .unavailable:
            return .unavailable
        }
    }

    static func mapError(_ error: MeshInferenceError) -> SaturnNodeError {
        switch error {
        case .modelUnavailable:
            return .modelNotAllowed
        case .capacityExhausted:
            return .nodeSaturated
        case .requestTimeout:
            return .requestTimedOut
        case .cancelled:
            return .cancelled
        case .notLoaded, .runtimeUnavailable:
            return .runtimeUnavailable
        case .generationFailed:
            return .malformedRequest("Mesh generation failed.")
        }
    }

    /// Deadline trip wins over a later mesh/library error.
    static func finishError(
        timedOut: Bool,
        deadline: Date,
        now: Date,
        otherwise: SaturnNodeError
    ) -> SaturnNodeError {
        if timedOut || now >= deadline {
            return .requestTimedOut
        }
        return otherwise
    }
}
