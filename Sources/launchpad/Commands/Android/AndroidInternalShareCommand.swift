import ArgumentParser
import Foundation

struct AndroidInternalShareCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "internal-share",
        abstract: "Upload AAB or APK to Android Internal App Sharing",
        subcommands: [
            AndroidInternalShareAABCommand.self,
            AndroidInternalShareAPKCommand.self,
        ]
    )
}

struct AndroidInternalShareAABCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "aab", abstract: "Upload AAB to Internal App Sharing")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Path to the AAB file")
    var aab: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name required"); Foundation.exit(1) }()

        guard FileManager.default.fileExists(atPath: aab) else {
            Logger.error("AAB file not found: \(aab)"); Foundation.exit(1)
        }

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Uploading \(aab) to Internal App Sharing for \(pkg)")
        let downloadURL = try await client.uploadInternalAppSharingAAB(packageName: pkg, aabPath: aab)
        Logger.success("Upload complete")
        print("\nShare link: \(downloadURL)")
    }
}

struct AndroidInternalShareAPKCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "apk", abstract: "Upload APK to Internal App Sharing")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Path to the APK file")
    var apk: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name required"); Foundation.exit(1) }()

        guard FileManager.default.fileExists(atPath: apk) else {
            Logger.error("APK file not found: \(apk)"); Foundation.exit(1)
        }

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Uploading \(apk) to Internal App Sharing for \(pkg)")
        let downloadURL = try await client.uploadInternalAppSharingAPK(packageName: pkg, apkPath: apk)
        Logger.success("Upload complete")
        print("\nShare link: \(downloadURL)")
    }
}
