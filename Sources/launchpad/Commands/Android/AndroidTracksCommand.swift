import ArgumentParser
import Foundation

struct AndroidTracksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tracks",
        abstract: "List all release tracks and their current releases"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching tracks for \(pkg)")
        let tracks = try await client.listTracks(packageName: pkg)

        if tracks.isEmpty { Logger.info("No tracks found"); return }
        Logger.info("\(tracks.count) track(s)\n")
        for t in tracks {
            let name     = t["track"] as? String ?? "-"
            let releases = t["releases"] as? [[String: Any]] ?? []
            print("  Track: \(name)")
            for r in releases {
                let status       = r["status"] as? String ?? "-"
                let name_        = r["name"] as? String ?? ""
                let versionCodes = (r["versionCodes"] as? [Any] ?? []).map { "\($0)" }.joined(separator: ", ")
                let userFraction = r["userFraction"] as? Double
                var line = "    [\(status)] versions: \(versionCodes.isEmpty ? "-" : versionCodes)"
                if let f = userFraction { line += "  rollout: \(Int(f * 100))%" }
                if !name_.isEmpty { line += "  name: \(name_)" }
                print(line)
            }
            print("")
        }
    }
}
