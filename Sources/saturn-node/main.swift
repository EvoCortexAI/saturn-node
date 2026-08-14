import Foundation
import SaturnNodeCore
import SaturnMLXMesh

@main
struct SaturnNodeBootstrap {
    static func main() async {
        let args = Set(CommandLine.arguments.dropFirst())

        if args.contains("--real-smoke") {
            await runRealSmoke()
            return
        }

        // Default: production composition is unavailable. No listener, no model load.
        do {
            _ = try SaturnNodeServiceComposition.unavailable()
        } catch {
            // Still fail closed; do not surface internal details.
        }

        FileHandle.standardError.write(
            Data("saturn-node: no network listener or inference runtime configured (pass --real-smoke for live MLX)\n".utf8)
        )
    }

    /// Explicit opt-in: load real weights and stream one request through the node adapter.
    /// Does not open a listener. Does not change default composition.
    private static func runRealSmoke() async {
        FileHandle.standardError.write(
            Data("saturn-node --real-smoke: loading \(AcceptanceModelPin.primaryModelID)\n".utf8)
        )

        do {
            let meshRuntime = try await MeshModelInferenceRuntime.loadPrimary()
            guard let nodeID = SaturnNodeIdentifier(rawValue: "saturn-node-local-smoke") else {
                FileHandle.standardError.write(Data("saturn-node --real-smoke: invalid node id\n".utf8))
                return
            }

            let adapter = MeshInferenceRuntimeAdapter(
                mesh: meshRuntime,
                nodeID: nodeID,
                serviceVersion: "0.0.0-real-smoke",
                acceptedCredentialEpoch: 0
            )

            let requestID = RequestIdentifier(UUID())
            // Nonce: 32 hex chars, no hyphens (allowed charset: alnum + _-).
            let nonceRaw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            guard let nonce = RequestNonce(rawValue: nonceRaw),
                  let deploymentID = DeploymentIdentifier(rawValue: "local-smoke"),
                  let workloadID = WorkloadIdentifier(rawValue: "local-smoke"),
                  let modelID = ModelIdentifier(rawValue: AcceptanceModelPin.primaryModelID) else {
                FileHandle.standardError.write(Data("saturn-node --real-smoke: identifier construction failed\n".utf8))
                return
            }

            let request = try SaturnNodeInferenceRequest(
                requestID: requestID,
                requestNonce: nonce,
                deploymentID: deploymentID,
                workloadID: workloadID,
                modelID: modelID,
                inputText: AcceptanceModelPin.acceptancePrompt,
                maximumContextTokens: 8192,
                maximumOutputTokens: AcceptanceModelPin.smokeMaxTokens,
                deadlineAt: Date().addingTimeInterval(120)
            )

            let stream = try await adapter.stream(request: request)
            var tokenCount = 0
            print("Tokens: ", terminator: "")
            for try await event in stream {
                switch event {
                case let .delta(_, _, text):
                    print(text, terminator: "")
                    fflush(stdout)
                    tokenCount += 1
                case .completed, .cancelled:
                    break
                default:
                    break
                }
            }
            print("\n")
            FileHandle.standardError.write(
                Data("saturn-node --real-smoke: completed (\(tokenCount) deltas). Real MLX path OK.\n".utf8)
            )
        } catch {
            FileHandle.standardError.write(
                Data("saturn-node --real-smoke: FAILED \(error)\n".utf8)
            )
        }
    }
}
