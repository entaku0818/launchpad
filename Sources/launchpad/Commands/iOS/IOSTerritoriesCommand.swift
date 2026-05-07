import ArgumentParser
import Foundation

struct IOSTerritoriesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "territories",
        abstract: "List all available App Store territories"
    )

    @Option(name: .long, help: "Filter by currency code (e.g. USD, JPY)")
    var currency: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching App Store territories")
        let territories = try await client.listAllTerritories()

        var filtered = territories
        if let cur = currency {
            filtered = territories.filter {
                ($0["attributes"] as? [String: Any])?["currency"] as? String == cur.uppercased()
            }
        }

        if filtered.isEmpty { Logger.info("No territories found"); return }
        Logger.info("\(filtered.count) territory/territories\n")
        let sorted = filtered.sorted {
            ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "")
        }
        let chunks = stride(from: 0, to: sorted.count, by: 6).map { Array(sorted[$0..<min($0 + 6, sorted.count)]) }
        for chunk in chunks {
            let line = chunk.compactMap { t -> String? in
                guard let id = t["id"] as? String else { return nil }
                let cur = (t["attributes"] as? [String: Any])?["currency"] as? String ?? ""
                return "\(id)(\(cur))"
            }.joined(separator: "  ")
            print("  " + line)
        }
    }
}
