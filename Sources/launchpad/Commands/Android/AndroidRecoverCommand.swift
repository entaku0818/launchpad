import ArgumentParser
import Foundation

struct AndroidRecoverCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recover",
        abstract: "Trigger app recovery to roll back a bad update"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Version code to roll back to")
    var versionCode: Int

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Triggering app recovery for \(pkg) → version code \(versionCode)")
        try await client.createRecovery(packageName: pkg, versionCode: versionCode)
        Logger.success("App recovery initiated. Affected users will be rolled back to version code \(versionCode).")
    }
}
