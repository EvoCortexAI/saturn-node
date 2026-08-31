import Foundation
import Testing
import SaturnMLXMesh
@testable import SaturnNodeCore

@Test(arguments: [
    (MeshInferenceError.modelUnavailable("missing"), SaturnNodeError.modelNotAllowed),
    (MeshInferenceError.capacityExhausted, SaturnNodeError.nodeSaturated),
    (MeshInferenceError.requestTimeout, SaturnNodeError.requestTimedOut),
    (MeshInferenceError.cancelled, SaturnNodeError.cancelled),
    (MeshInferenceError.notLoaded, SaturnNodeError.runtimeUnavailable),
    (MeshInferenceError.runtimeUnavailable, SaturnNodeError.runtimeUnavailable),
    (MeshInferenceError.generationFailed("boom"), SaturnNodeError.malformedRequest("Mesh generation failed."))
] as [(MeshInferenceError, SaturnNodeError)])
func mapsMeshErrorsFailClosed(_ meshError: MeshInferenceError, _ expected: SaturnNodeError) {
    #expect(MeshRuntimeMapping.mapError(meshError) == expected)
}

@Test
func mapsRuntimeStates() {
    #expect(MeshRuntimeMapping.mapState(.available) == .available)
    #expect(MeshRuntimeMapping.mapState(.saturated) == .saturated)
    #expect(MeshRuntimeMapping.mapState(.unavailable) == .unavailable)
}

@Test
func expiredDeadlineFailsClosedBeforeGeneration() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(throws: SaturnNodeError.requestTimedOut) {
        try MeshRuntimeMapping.requireFreshDeadline(now.addingTimeInterval(-1), now: now)
    }
}

@Test
func futureDeadlineIsAdmitted() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try MeshRuntimeMapping.requireFreshDeadline(now.addingTimeInterval(30), now: now)
}

@Test
func deadlineEqualityIsExpired() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(throws: SaturnNodeError.requestTimedOut) {
        try MeshRuntimeMapping.requireFreshDeadline(now, now: now)
    }
}

@Test
func finishErrorPrefersTimeoutOnceDeadlineTrips() {
    let now = Date(timeIntervalSince1970: 1_700_000_010)
    let deadline = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(
        MeshRuntimeMapping.finishError(
            timedOut: false,
            deadline: deadline,
            now: now,
            otherwise: .nodeSaturated
        ) == .requestTimedOut
    )
    #expect(
        MeshRuntimeMapping.finishError(
            timedOut: true,
            deadline: now.addingTimeInterval(60),
            now: now,
            otherwise: .cancelled
        ) == .requestTimedOut
    )
    #expect(
        MeshRuntimeMapping.finishError(
            timedOut: false,
            deadline: now.addingTimeInterval(60),
            now: now,
            otherwise: .nodeSaturated
        ) == .nodeSaturated
    )
}
