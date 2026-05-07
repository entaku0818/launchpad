import ArgumentParser
import Foundation

struct AndroidAppDetailsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "app-details",
        abstract: "Read and update Play Store app-level details (contact info, default language)",
        subcommands: [
            AndroidAppDetailsGetCommand.self,
            AndroidAppDetailsUpdateCommand.self,
        ]
    )
}

struct AndroidAppDetailsGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show app details from the current draft edit")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching app details for \(pkg)")
        let details = try await client.getAppDetails(packageName: pkg)

        let lang    = details["defaultLanguage"] as? String ?? "-"
        let email   = details["contactEmail"] as? String ?? "-"
        let phone   = details["contactPhone"] as? String ?? ""
        let website = details["contactWebsite"] as? String ?? ""

        print("Default language: \(lang)")
        print("Contact email:    \(email)")
        if !phone.isEmpty   { print("Contact phone:    \(phone)") }
        if !website.isEmpty { print("Contact website:  \(website)") }
    }
}

struct AndroidAppDetailsUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update app-level details (commits the edit)")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Default language code (e.g. en-US)")
    var defaultLanguage: String?

    @Option(name: .long, help: "Developer contact email")
    var contactEmail: String?

    @Option(name: .long, help: "Developer contact phone")
    var contactPhone: String?

    @Option(name: .long, help: "Developer contact website URL")
    var contactWebsite: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Updating app details for \(pkg)")
        try await client.updateAppDetails(
            packageName: pkg,
            defaultLanguage: defaultLanguage,
            contactEmail: contactEmail,
            contactPhone: contactPhone,
            contactWebsite: contactWebsite
        )
        Logger.success("App details updated and edit committed")
    }
}
