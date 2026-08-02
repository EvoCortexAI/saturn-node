import Foundation

// MARK: - Immutable configuration

/// Production node configuration. All bounds are explicit; zero or negative values fail closed.
public struct SaturnNodeServiceConfiguration: Hashable, Sendable {
    public let nodeID: SaturnNodeIdentifier
    public let serviceVersion: String
    public let maximumConcurrentRequests: Int
    public let clockSkewAllowance: TimeInterval
    public let contractVersion: String

    public init(
        nodeID: SaturnNodeIdentifier,
        serviceVersion: String,
        maximumConcurrentRequests: Int,
        clockSkewAllowance: TimeInterval = 30,
        contractVersion: String = SaturnNodeInferenceRequest.supportedContractVersion
    ) throws {
        guard contractVersion == SaturnNodeInferenceRequest.supportedContractVersion else {
            throw SaturnNodeError.unsupportedContractVersion(contractVersion)
        }
        guard !serviceVersion.isEmpty, serviceVersion.count <= 64 else {
            throw SaturnNodeError.invalidServiceConfiguration("serviceVersion")
        }
        guard maximumConcurrentRequests > 0, maximumConcurrentRequests <= 1024 else {
            throw SaturnNodeError.invalidServiceConfiguration("maximumConcurrentRequests")
        }
        guard clockSkewAllowance >= 0, clockSkewAllowance <= 300 else {
            throw SaturnNodeError.invalidServiceConfiguration("clockSkewAllowance")
        }

        self.nodeID = nodeID
        self.serviceVersion = serviceVersion
        self.maximumConcurrentRequests = maximumConcurrentRequests
        self.clockSkewAllowance = clockSkewAllowance
        self.contractVersion = contractVersion
    }
}

// MARK: - Protocols (seams only; no crypto, no networking)

public protocol NodeIdentityProviding: Sendable {
    func currentNodeID() async throws -> SaturnNodeIdentifier
}

public protocol RevocationStateProviding: Sendable {
    func acceptedEpoch() async throws -> Int
    func isRevoked(credentialID: CredentialIdentifier) async throws -> Bool
}

public protocol ReplayProtectionProviding: Sendable {
    func hasSeen(requestID: RequestIdentifier, nonce: RequestNonce) async throws -> Bool
    func record(requestID: RequestIdentifier, nonce: RequestNonce) async throws
}

public protocol ModelAllowlistProviding: Sendable {
    func isAllowed(modelID: ModelIdentifier) async throws -> Bool
}

public protocol AdmissionControlling: Sendable {
    /// Returns current active request count before admission.
    func activeCount() async -> Int
    /// Attempts to reserve a slot. Throws `nodeSaturated` or `serviceDraining` when denied.
    func tryAdmit(requestID: RequestIdentifier) async throws
    /// Releases a previously admitted request exactly once.
    func release(requestID: RequestIdentifier) async
}

public protocol ServiceLifecycleControlling: Sendable {
    var isDraining: Bool { get async }
    func beginDrain() async
}

// MARK: - Unavailable / fail-closed defaults

public struct UnavailableNodeIdentity: NodeIdentityProviding {
    public init() {}
    public func currentNodeID() async throws -> SaturnNodeIdentifier {
        throw SaturnNodeError.identityUnavailable
    }
}

public struct UnavailableRevocationState: RevocationStateProviding {
    public init() {}
    public func acceptedEpoch() async throws -> Int {
        throw SaturnNodeError.revocationStateUnavailable
    }
    public func isRevoked(credentialID: CredentialIdentifier) async throws -> Bool {
        throw SaturnNodeError.revocationStateUnavailable
    }
}

public struct UnavailableReplayProtection: ReplayProtectionProviding {
    public init() {}
    public func hasSeen(requestID: RequestIdentifier, nonce: RequestNonce) async throws -> Bool {
        throw SaturnNodeError.replayProtectionUnavailable
    }
    public func record(requestID: RequestIdentifier, nonce: RequestNonce) async throws {
        throw SaturnNodeError.replayProtectionUnavailable
    }
}

public struct UnavailableModelAllowlist: ModelAllowlistProviding {
    public init() {}
    public func isAllowed(modelID: ModelIdentifier) async throws -> Bool {
        throw SaturnNodeError.modelAllowlistUnavailable
    }
}

public struct UnavailableAdmissionController: AdmissionControlling {
    public init() {}
    public func activeCount() async -> Int { 0 }
    public func tryAdmit(requestID: RequestIdentifier) async throws {
        throw SaturnNodeError.admissionUnavailable
    }
    public func release(requestID: RequestIdentifier) async {}
}

public struct UnavailableServiceLifecycle: ServiceLifecycleControlling {
    public init() {}
    public var isDraining: Bool { get async { true } }
    public func beginDrain() async {}
}

// MARK: - Deterministic test doubles (not for production)

public actor InMemoryRevocationState: RevocationStateProviding {
    private var epoch: Int
    private var revoked: Set<CredentialIdentifier>

    public init(epoch: Int = 0, revoked: Set<CredentialIdentifier> = []) {
        self.epoch = max(0, epoch)
        self.revoked = revoked
    }

    public func acceptedEpoch() async throws -> Int { epoch }
    public func isRevoked(credentialID: CredentialIdentifier) async throws -> Bool {
        revoked.contains(credentialID)
    }
    public func revoke(_ id: CredentialIdentifier) {
        revoked.insert(id)
    }
}

public actor InMemoryReplayProtection: ReplayProtectionProviding {
    private var seenIDs: Set<RequestIdentifier> = []
    private var seenNonces: Set<RequestNonce> = []

    public init() {}

    public func hasSeen(requestID: RequestIdentifier, nonce: RequestNonce) async throws -> Bool {
        seenIDs.contains(requestID) || seenNonces.contains(nonce)
    }

    public func record(requestID: RequestIdentifier, nonce: RequestNonce) async throws {
        seenIDs.insert(requestID)
        seenNonces.insert(nonce)
    }
}

public struct StaticNodeIdentity: NodeIdentityProviding {
    public let nodeID: SaturnNodeIdentifier
    public init(nodeID: SaturnNodeIdentifier) { self.nodeID = nodeID }
    public func currentNodeID() async throws -> SaturnNodeIdentifier { nodeID }
}

public struct StaticModelAllowlist: ModelAllowlistProviding {
    public let allowed: Set<ModelIdentifier>
    public init(allowed: Set<ModelIdentifier>) { self.allowed = allowed }
    public func isAllowed(modelID: ModelIdentifier) async throws -> Bool {
        allowed.contains(modelID)
    }
}

public actor BoundedAdmissionController: AdmissionControlling {
    private let maximum: Int
    private var active: Set<RequestIdentifier> = []
    private var draining = false

    public init(maximum: Int) {
        self.maximum = max(0, maximum)
    }

    public func activeCount() async -> Int { active.count }

    public func tryAdmit(requestID: RequestIdentifier) async throws {
        if draining {
            throw SaturnNodeError.serviceDraining
        }
        guard active.count < maximum else {
            throw SaturnNodeError.nodeSaturated
        }
        guard !active.contains(requestID) else {
            throw SaturnNodeError.replayedCredential
        }
        active.insert(requestID)
    }

    public func release(requestID: RequestIdentifier) async {
        active.remove(requestID)
    }

    public func beginDrain() {
        draining = true
    }

    public var isDraining: Bool { draining }
}

public actor SimpleServiceLifecycle: ServiceLifecycleControlling {
    private var draining = false
    public init() {}
    public var isDraining: Bool { get async { draining } }
    public func beginDrain() async { draining = true }
}

// MARK: - Composition

/// Assembles the seams required for a future secure service.
/// Production composition is only constructible when every required dependency is supplied.
/// The ordinary executable path uses `unavailable()` and never opens a listener.
public struct SaturnNodeServiceComposition: Sendable {
    public let configuration: SaturnNodeServiceConfiguration
    public let identity: any NodeIdentityProviding
    public let verifier: any WorkloadCredentialVerifying
    public let revocation: any RevocationStateProviding
    public let replay: any ReplayProtectionProviding
    public let allowlist: any ModelAllowlistProviding
    public let admission: any AdmissionControlling
    public let runtime: any SaturnNodeInferenceRuntime
    public let lifecycle: any ServiceLifecycleControlling

    /// Fail-closed factory used by the production executable and by default tests.
    public static func unavailable() throws -> SaturnNodeServiceComposition {
        // Configuration still validates; identity and all other deps are unavailable.
        let placeholderNode = try #require(SaturnNodeIdentifier(rawValue: "unavailable-node"))
        let configuration = try SaturnNodeServiceConfiguration(
            nodeID: placeholderNode,
            serviceVersion: "0.0.0-unavailable",
            maximumConcurrentRequests: 1
        )
        return SaturnNodeServiceComposition(
            configuration: configuration,
            identity: UnavailableNodeIdentity(),
            verifier: UnavailableWorkloadCredentialVerifier(),
            revocation: UnavailableRevocationState(),
            replay: UnavailableReplayProtection(),
            allowlist: UnavailableModelAllowlist(),
            admission: UnavailableAdmissionController(),
            runtime: UnavailableInferenceRuntime(),
            lifecycle: UnavailableServiceLifecycle()
        )
    }

    /// Explicit production-style assembly. Caller must supply real implementations.
    /// Does not open sockets, load models, or choose a credential format.
    public init(
        configuration: SaturnNodeServiceConfiguration,
        identity: any NodeIdentityProviding,
        verifier: any WorkloadCredentialVerifying,
        revocation: any RevocationStateProviding,
        replay: any ReplayProtectionProviding,
        allowlist: any ModelAllowlistProviding,
        admission: any AdmissionControlling,
        runtime: any SaturnNodeInferenceRuntime,
        lifecycle: any ServiceLifecycleControlling
    ) {
        self.configuration = configuration
        self.identity = identity
        self.verifier = verifier
        self.revocation = revocation
        self.replay = replay
        self.allowlist = allowlist
        self.admission = admission
        self.runtime = runtime
        self.lifecycle = lifecycle
    }

    /// Authorizes and admits a request using injected seams, then hands off to the runtime.
    /// Domain authorization semantics (WorkloadClaimValidator) remain independent of future cryptography.
    public func authorizeAndStream(
        presentation: Data,
        request: SaturnNodeInferenceRequest,
        now: Date
    ) async throws -> AsyncThrowingStream<SaturnNodeInferenceEvent, Error> {
        if await lifecycle.isDraining {
            throw SaturnNodeError.serviceDraining
        }

        let nodeID = try await identity.currentNodeID()
        guard nodeID == configuration.nodeID else {
            throw SaturnNodeError.wrongNode
        }

        let claims = try await verifier.verify(presentation: presentation)

        let acceptedEpoch = try await revocation.acceptedEpoch()
        let isRevoked = try await revocation.isRevoked(credentialID: claims.credentialID)
        let alreadySeen = try await replay.hasSeen(
            requestID: request.requestID,
            nonce: request.requestNonce
        )

        guard try await allowlist.isAllowed(modelID: request.modelID) else {
            throw SaturnNodeError.modelNotAllowed
        }

        let active = await admission.activeCount()
        let context = WorkloadAuthorizationContext(
            expectedNodeID: configuration.nodeID,
            expectedWorkloadID: request.workloadID,
            expectedDeploymentID: request.deploymentID,
            requestedModelID: request.modelID,
            acceptedEpoch: acceptedEpoch,
            clockSkewAllowance: configuration.clockSkewAllowance,
            activeConcurrentRequests: active,
            consumedRequestCount: 0,
            consumedTokenCount: 0,
            revokedCredentialIDs: isRevoked ? [claims.credentialID] : [],
            seenRequestIDs: alreadySeen ? [request.requestID] : [],
            seenRequestNonces: alreadySeen ? [request.requestNonce] : []
        )

        try WorkloadClaimValidator.validate(
            claims: claims,
            request: request,
            context: context,
            now: now
        )

        // Admission only after all authorization checks pass.
        try await admission.tryAdmit(requestID: request.requestID)
        try await replay.record(requestID: request.requestID, nonce: request.requestNonce)

        do {
            let stream = try await runtime.stream(request: request)
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await event in stream {
                            continuation.yield(event)
                            if event.isTerminal {
                                break
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                    await admission.release(requestID: request.requestID)
                }
                continuation.onTermination = { _ in
                    task.cancel()
                    Task { await admission.release(requestID: request.requestID) }
                }
            }
        } catch {
            await admission.release(requestID: request.requestID)
            throw error
        }
    }
}
