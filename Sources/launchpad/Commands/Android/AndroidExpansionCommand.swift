import ArgumentParser
import Foundation

struct AndroidExpansionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "expansion",
        abstract: "Manage OBB expansion files",
        subcommands: [
            AndroidExpansionGetCommand.self,
            AndroidExpansionUploadCommand.self,
        ]
    )
}

struct AndroidExpansionGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show expansion file info for an APK")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "APK version code")
    var versionCode: Int

    @Option(name: .long, help: "File type: main or patch (default: main)")
    var fileType: String = "main"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching \(fileType) expansion file for versionCode \(versionCode)")
        let info = try await client.getExpansionFile(packageName: pkg, versionCode: versionCode, fileType: fileType)

        let fileSize  = info["fileSize"] as? Int ?? 0
        let refsVer   = info["referencesVersion"] as? Int
        print("\nfileSize: \(fileSize) bytes (\(fileSize / 1024 / 1024) MB)")
        if let ref = refsVer { print("referencesVersion: \(ref)") }
    }
}

struct AndroidExpansionUploadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "upload", abstract: "Upload an OBB expansion file")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "APK version code")
    var versionCode: Int

    @Option(name: .long, help: "File type: main or patch (default: main)")
    var fileType: String = "main"

    @Option(name: .long, help: "Path to .obb file")
    var file: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        guard FileManager.default.fileExists(atPath: file) else {
            Logger.error("File not found: \(file)"); Foundation.exit(1)
        }

        let client = try GooglePlayClient.fromEnvironment()
        let sizeMB = (try? Data(contentsOf: URL(fileURLWithPath: file)).count / 1024 / 1024) ?? 0
        Logger.step("Uploading \(fileType) expansion file (\(sizeMB) MB) for versionCode \(versionCode)")
        try await client.uploadExpansionFile(packageName: pkg, versionCode: versionCode, fileType: fileType, filePath: file)
        Logger.success("Expansion file uploaded and published")
    }
}
