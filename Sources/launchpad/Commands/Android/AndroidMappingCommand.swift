import ArgumentParser
import Foundation

struct AndroidMappingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mapping",
        abstract: "Upload ProGuard/R8 mapping file for crash deobfuscation"
    )

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Version code the mapping file corresponds to")
    var versionCode: Int

    @Option(name: .long, help: "Path to mapping.txt file")
    var mapping: String = "app/build/outputs/mapping/release/mapping.txt"

    @Option(name: .long, help: "File type: proguard or nativeCode (default: proguard)")
    var fileType: String = "proguard"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        guard fileType == "proguard" || fileType == "nativeCode" else {
            Logger.error("--file-type must be 'proguard' or 'nativeCode'")
            Foundation.exit(1)
        }

        guard FileManager.default.fileExists(atPath: mapping) else {
            Logger.error("Mapping file not found: \(mapping)")
            Foundation.exit(1)
        }

        let client = try GooglePlayClient.fromEnvironment()

        Logger.step("Uploading \(fileType) mapping for \(pkg) versionCode \(versionCode)")
        try await client.uploadMapping(packageName: pkg, versionCode: versionCode, mappingPath: mapping, fileType: fileType)
        Logger.success("Mapping uploaded — crashes for version \(versionCode) will be deobfuscated in Play Console")
    }
}
