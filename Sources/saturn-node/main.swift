import Foundation

@main
struct SaturnNodeBootstrap {
    static func main() {
        FileHandle.standardError.write(
            Data("saturn-node bootstrap: no network listener or inference runtime is configured\n".utf8)
        )
    }
}
