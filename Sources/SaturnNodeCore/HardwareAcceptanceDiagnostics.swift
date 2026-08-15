public extension SaturnNodeHardwareAcceptanceError {
    /// Stable metadata-only code for acceptance logs.
    ///
    /// Do not include associated values here: hardware evidence must not echo
    /// caller-provided strings or other potentially sensitive details.
    var diagnosticCode: String {
        switch self {
        case .invalidRequestCount:
            "invalid_request_count"
        case .invalidCancellationCount:
            "invalid_cancellation_count"
        case .missingArgumentValue:
            "missing_argument_value"
        case .invalidArgumentValue:
            "invalid_argument_value"
        case .emptyTimingSamples:
            "empty_timing_samples"
        case .missingStarted:
            "missing_started"
        case .noGeneratedDeltas:
            "no_generated_deltas"
        case .missingCompletion:
            "missing_completion"
        case .unexpectedCancellation:
            "unexpected_cancellation"
        case .cancellationNotObserved:
            "cancellation_not_observed"
        case .runtimeNotQuiescent:
            "runtime_not_quiescent"
        }
    }
}
