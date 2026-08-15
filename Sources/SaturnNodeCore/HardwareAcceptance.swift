import Foundation

public enum SaturnNodeHardwareAcceptanceError: Error, Equatable, Sendable {
    case invalidRequestCount(Int)
    case invalidCancellationCount(Int)
    case missingArgumentValue(String)
    case invalidArgumentValue(String, String)
    case emptyTimingSamples
    case missingStarted
    case noGeneratedDeltas
    case missingCompletion
    case unexpectedCancellation
    case cancellationNotObserved
    case runtimeNotQuiescent
}

public enum SaturnNodeHardwareAcceptanceRequestKind: Sendable {
    case ordinary
    case cancellation
    case recovery
}

public struct SaturnNodeHardwareAcceptanceConfiguration: Equatable, Sendable {
    public let requestCount: Int
    public let cancellationCount: Int

    public init(requestCount: Int, cancellationCount: Int) throws {
        guard (1...1_000).contains(requestCount) else {
            throw SaturnNodeHardwareAcceptanceError.invalidRequestCount(requestCount)
        }
        guard (0...1_000).contains(cancellationCount) else {
            throw SaturnNodeHardwareAcceptanceError.invalidCancellationCount(cancellationCount)
        }
        self.requestCount = requestCount
        self.cancellationCount = cancellationCount
    }

    /// Parses only hardware-acceptance count flags and ignores unrelated smoke flags.
    ///
    /// `--cancel-recovery` remains a compatibility alias for one cancellation cycle
    /// unless an explicit `--cancellations N` value is supplied.
    public init(arguments: [String]) throws {
        var requestCount = 1
        var cancellationCount = arguments.contains("--cancel-recovery") ? 1 : 0
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--requests":
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw SaturnNodeHardwareAcceptanceError.missingArgumentValue(argument)
                }
                let value = arguments[valueIndex]
                guard let parsed = Int(value) else {
                    throw SaturnNodeHardwareAcceptanceError.invalidArgumentValue(argument, value)
                }
                requestCount = parsed
                index = valueIndex

            case "--cancellations":
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw SaturnNodeHardwareAcceptanceError.missingArgumentValue(argument)
                }
                let value = arguments[valueIndex]
                guard let parsed = Int(value) else {
                    throw SaturnNodeHardwareAcceptanceError.invalidArgumentValue(argument, value)
                }
                cancellationCount = parsed
                index = valueIndex

            default:
                break
            }
            index += 1
        }

        try self.init(
            requestCount: requestCount,
            cancellationCount: cancellationCount
        )
    }
}

public struct SaturnNodeHardwareAcceptanceCompletionSample: Sendable {
    public let deltaCount: Int
    public let timeToFirstDelta: Duration
    public let generationDuration: Duration
    public let finishReason: SaturnNodeInferenceFinishReason

    public init(
        deltaCount: Int,
        timeToFirstDelta: Duration,
        generationDuration: Duration,
        finishReason: SaturnNodeInferenceFinishReason
    ) {
        self.deltaCount = deltaCount
        self.timeToFirstDelta = timeToFirstDelta
        self.generationDuration = generationDuration
        self.finishReason = finishReason
    }
}

public struct SaturnNodeHardwareAcceptanceCancellationSample: Sendable {
    public let deltaCountBeforeCancellation: Int
    public let cancellationDuration: Duration

    public init(
        deltaCountBeforeCancellation: Int,
        cancellationDuration: Duration
    ) {
        self.deltaCountBeforeCancellation = deltaCountBeforeCancellation
        self.cancellationDuration = cancellationDuration
    }
}

public struct SaturnNodeHardwareAcceptanceReport: Sendable {
    public let ordinarySamples: [SaturnNodeHardwareAcceptanceCompletionSample]
    public let cancellationSamples: [SaturnNodeHardwareAcceptanceCancellationSample]
    public let recoverySamples: [SaturnNodeHardwareAcceptanceCompletionSample]

    public init(
        ordinarySamples: [SaturnNodeHardwareAcceptanceCompletionSample],
        cancellationSamples: [SaturnNodeHardwareAcceptanceCancellationSample],
        recoverySamples: [SaturnNodeHardwareAcceptanceCompletionSample]
    ) {
        self.ordinarySamples = ordinarySamples
        self.cancellationSamples = cancellationSamples
        self.recoverySamples = recoverySamples
    }
}

public struct SaturnNodeHardwareAcceptanceTimingSummary: Equatable, Sendable {
    public let minimumMilliseconds: Double
    public let medianMilliseconds: Double
    public let p95Milliseconds: Double

    public init(samples: [Duration]) throws {
        guard !samples.isEmpty else {
            throw SaturnNodeHardwareAcceptanceError.emptyTimingSamples
        }

        let values = samples.map(Self.milliseconds).sorted()
        minimumMilliseconds = values[0]

        let midpoint = values.count / 2
        if values.count.isMultiple(of: 2) {
            medianMilliseconds = (values[midpoint - 1] + values[midpoint]) / 2
        } else {
            medianMilliseconds = values[midpoint]
        }

        let nearestRank = max(1, Int(ceil(Double(values.count) * 0.95)))
        p95Milliseconds = values[nearestRank - 1]
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}

/// Runs the sustained Node-adapter acceptance sequence against one already-loaded runtime.
///
/// The runner is runtime-agnostic so deterministic CI can exercise the same request,
/// cancellation, recovery, sequencing, and quiescence logic used by real hardware.
/// It never loads models, opens a listener, or selects production composition.
public struct SaturnNodeHardwareAcceptanceRunner: Sendable {
    public typealias RequestFactory = @Sendable (
        SaturnNodeHardwareAcceptanceRequestKind
    ) throws -> SaturnNodeInferenceRequest
    public typealias QuiescenceCheck = @Sendable () async -> Bool
    public typealias DeltaObserver = @Sendable (String) -> Void

    private let runtime: any SaturnNodeInferenceRuntime
    private let configuration: SaturnNodeHardwareAcceptanceConfiguration
    private let makeRequest: RequestFactory
    private let isQuiescent: QuiescenceCheck
    private let observeDelta: DeltaObserver

    public init(
        runtime: any SaturnNodeInferenceRuntime,
        configuration: SaturnNodeHardwareAcceptanceConfiguration,
        makeRequest: @escaping RequestFactory,
        isQuiescent: @escaping QuiescenceCheck,
        observeDelta: @escaping DeltaObserver = { _ in }
    ) {
        self.runtime = runtime
        self.configuration = configuration
        self.makeRequest = makeRequest
        self.isQuiescent = isQuiescent
        self.observeDelta = observeDelta
    }

    public func run() async throws -> SaturnNodeHardwareAcceptanceReport {
        var ordinarySamples: [SaturnNodeHardwareAcceptanceCompletionSample] = []
        ordinarySamples.reserveCapacity(configuration.requestCount)

        for _ in 0..<configuration.requestCount {
            let request = try makeRequest(.ordinary)
            ordinarySamples.append(try await runCompletion(request: request))
            try await requireQuiescence()
        }

        var cancellationSamples: [SaturnNodeHardwareAcceptanceCancellationSample] = []
        var recoverySamples: [SaturnNodeHardwareAcceptanceCompletionSample] = []
        cancellationSamples.reserveCapacity(configuration.cancellationCount)
        recoverySamples.reserveCapacity(configuration.cancellationCount)

        for _ in 0..<configuration.cancellationCount {
            let cancellationRequest = try makeRequest(.cancellation)
            cancellationSamples.append(
                try await runCancellation(request: cancellationRequest)
            )
            try await requireQuiescence()

            let recoveryRequest = try makeRequest(.recovery)
            recoverySamples.append(try await runCompletion(request: recoveryRequest))
            try await requireQuiescence()
        }

        return SaturnNodeHardwareAcceptanceReport(
            ordinarySamples: ordinarySamples,
            cancellationSamples: cancellationSamples,
            recoverySamples: recoverySamples
        )
    }

    private func runCompletion(
        request: SaturnNodeInferenceRequest
    ) async throws -> SaturnNodeHardwareAcceptanceCompletionSample {
        let stream = try await runtime.stream(request: request)
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
                observeDelta(text)

            case let .completed(_, _, reason):
                finishReason = reason

            case .cancelled:
                throw SaturnNodeHardwareAcceptanceError.unexpectedCancellation

            case .usage:
                break
            }
        }

        guard sawStarted else {
            throw SaturnNodeHardwareAcceptanceError.missingStarted
        }
        guard deltaCount > 0, let firstDeltaAt else {
            throw SaturnNodeHardwareAcceptanceError.noGeneratedDeltas
        }
        guard let finishReason else {
            throw SaturnNodeHardwareAcceptanceError.missingCompletion
        }

        return SaturnNodeHardwareAcceptanceCompletionSample(
            deltaCount: deltaCount,
            timeToFirstDelta: startedAt.duration(to: firstDeltaAt),
            generationDuration: startedAt.duration(to: clock.now),
            finishReason: finishReason
        )
    }

    private func runCancellation(
        request: SaturnNodeInferenceRequest
    ) async throws -> SaturnNodeHardwareAcceptanceCancellationSample {
        let stream = try await runtime.stream(request: request)
        let clock = ContinuousClock()
        let startedAt = clock.now
        var deltaCount = 0
        var sawStarted = false
        var cancellationRequested = false
        var cancellationObserved = false
        var sequenceValidator = SaturnNodeInferenceEventSequenceValidator()

        for try await event in stream {
            try sequenceValidator.accept(event)

            switch event {
            case .started:
                sawStarted = true

            case let .delta(_, _, text):
                guard !text.isEmpty else { continue }
                deltaCount += 1
                observeDelta(text)
                if !cancellationRequested {
                    cancellationRequested = true
                    try await runtime.cancel(requestID: request.requestID)
                }

            case .cancelled:
                cancellationObserved = true

            case .completed:
                throw SaturnNodeHardwareAcceptanceError.cancellationNotObserved

            case .usage:
                break
            }
        }

        guard sawStarted else {
            throw SaturnNodeHardwareAcceptanceError.missingStarted
        }
        guard cancellationRequested, cancellationObserved, deltaCount > 0 else {
            throw SaturnNodeHardwareAcceptanceError.cancellationNotObserved
        }

        return SaturnNodeHardwareAcceptanceCancellationSample(
            deltaCountBeforeCancellation: deltaCount,
            cancellationDuration: startedAt.duration(to: clock.now)
        )
    }

    private func requireQuiescence() async throws {
        guard await isQuiescent() else {
            throw SaturnNodeHardwareAcceptanceError.runtimeNotQuiescent
        }
    }
}
