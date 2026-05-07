import ArgumentParser
import Foundation

struct AndroidSystemApksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "system-apks",
        abstract: "Manage system APK variants for pre-installed apps",
        subcommands: [
            AndroidSystemApksListCommand.self,
            AndroidSystemApksCreateCommand.self,
        ]
    )
}

struct AndroidSystemApksListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List system APK variants for a version code")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Version code")
    var versionCode: Int

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching system APK variants for \(pkg) versionCode \(versionCode)")
        let variants = try await client.listSystemApks(packageName: pkg, versionCode: versionCode)

        if variants.isEmpty { Logger.info("No system APK variants found"); return }
        Logger.info("\(variants.count) variant(s)\n")
        for v in variants {
            let variantID  = v["variantId"] as? Int ?? -1
            let deviceSpec = v["deviceSpec"] as? [String: Any] ?? [:]
            let abis       = (deviceSpec["supportedAbis"] as? [String] ?? []).joined(separator: ", ")
            let screenDens = deviceSpec["screenDensity"] as? Int ?? 0
            let sdkVersion = deviceSpec["sdkVersion"] as? Int ?? 0
            print("  variantId: \(variantID)")
            print("    abis: \(abis.isEmpty ? "-" : abis)  density: \(screenDens)  sdk: \(sdkVersion)\n")
        }
    }
}

struct AndroidSystemApksCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a system APK variant")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Version code")
    var versionCode: Int

    @Option(name: .long, help: "Comma-separated supported ABIs (e.g. armeabi-v7a,arm64-v8a)")
    var abis: String = "arm64-v8a"

    @Option(name: .long, help: "Screen density (e.g. 480)")
    var screenDensity: Int = 480

    @Option(name: .long, help: "Minimum SDK version")
    var sdkVersion: Int = 21

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name required"); Foundation.exit(1) }()

        let abiList = abis.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let deviceSpec: [String: Any] = [
            "supportedAbis": abiList,
            "screenDensity": screenDensity,
            "sdkVersion": sdkVersion,
        ]

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Creating system APK variant for \(pkg) versionCode \(versionCode)")
        let variantID = try await client.createSystemApkVariant(packageName: pkg, versionCode: versionCode, deviceSpec: deviceSpec)
        Logger.success("System APK variant created: variantId \(variantID)")
    }
}
