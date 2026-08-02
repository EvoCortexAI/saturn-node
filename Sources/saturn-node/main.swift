import Foundation
import SaturnNodeCore

@main
struct SaturnNodeBootstrap {
    static func main() {
        // Production composition is unavailable. No listener, no model load, no inference.
        do {
            _ = try SaturnNodeServiceComposition.unavailable()
        } catch {
            // Still fail closed; do not surface internal details that could leak secrets.
        }

        FileHandle.standardError.write(
            Data("saturn-node bootstrap: no network listener or inference runtime is configured\n".utf8)
        )
    }
}
