import ArgumentParser
import Foundation

struct AndroidCountriesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "countries",
        abstract: "Manage country availability per track",
        subcommands: [
            AndroidCountriesListCommand.self,
            AndroidCountriesSetCommand.self,
        ]
    )
}

struct AndroidCountriesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "Show country availability for a track")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Track (internal/alpha/beta/production)")
    var track: String = "production"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching country availability for \(track)")
        let (countries, restOfWorld) = try await client.getCountryAvailability(packageName: pkg, track: track)

        Logger.info("includeRestOfWorld: \(restOfWorld)")
        if countries.isEmpty {
            Logger.info("No specific countries set")
        } else {
            Logger.info("\(countries.count) specific country/countries:\n")
            let rows = countries.chunks(ofCount: 10).map { $0.joined(separator: "  ") }
            rows.forEach { print("  \($0)") }
        }
    }
}

struct AndroidCountriesSetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Set country availability for a track")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Track (internal/alpha/beta/production)")
    var track: String = "production"

    @Option(name: .long, help: "Comma-separated ISO 3166-1 alpha-2 country codes (e.g. JP,US,GB)")
    var countries: String

    @Flag(name: .long, help: "Also include rest of world not in the list")
    var restOfWorld: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let codes = countries.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Setting \(track) availability to \(codes.count) countries (restOfWorld: \(restOfWorld))")
        try await client.setCountryAvailability(packageName: pkg, track: track, countries: codes, restOfWorld: restOfWorld)
        Logger.success("Country availability updated")
    }
}

private extension Array {
    func chunks(ofCount size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
