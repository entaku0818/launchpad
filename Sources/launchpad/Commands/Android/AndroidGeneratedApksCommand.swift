import ArgumentParser
import Foundation

struct AndroidGeneratedApksCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generated-apks",
        abstract: "List and download APKs generated from an AAB upload",
        subcommands: [
            AndroidGeneratedApksListCommand.self,
            AndroidGeneratedApksDownloadCommand.self,
        ]
    )
}

struct AndroidGeneratedApksListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List generated APKs for a version code")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Version code")
    var versionCode: Int

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching generated APKs for \(pkg) versionCode \(versionCode)")
        let apks = try await client.listGeneratedApks(packageName: pkg, versionCode: versionCode)

        if apks.isEmpty { Logger.info("No generated APKs found"); return }
        Logger.info("\(apks.count) APK(s)\n")
        for a in apks {
            let downloadID    = a["downloadId"] as? String ?? a["certificateSha256Hash"] as? String ?? "-"
            let abi           = a["targetingInfo"] as? [String: Any]
            let abiFilter     = (abi?["abiAlias"] as? String) ?? "-"
            let language      = (abi?["languageTargeting"] as? [String: Any]).flatMap { $0["value"] as? [String] }?.first ?? ""
            let isSplitApk    = a["isSplitApk"] as? Bool ?? false
            print("  downloadId: \(downloadID)")
            print("    abi: \(abiFilter)  splitApk: \(isSplitApk)\(language.isEmpty ? "" : "  lang: \(language)")\n")
        }
    }
}

struct AndroidGeneratedApksDownloadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "download", abstract: "Download a specific generated APK")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Version code")
    var versionCode: Int

    @Option(name: .long, help: "Download ID (from generated-apks list)")
    var downloadID: String

    @Option(name: .long, help: "Output file path (default: <downloadID>.apk)")
    var output: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name required"); Foundation.exit(1) }()

        let dest = output ?? "\(downloadID).apk"
        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Downloading generated APK \(downloadID) → \(dest)")
        try await client.downloadGeneratedApk(packageName: pkg, versionCode: versionCode, downloadID: downloadID, destination: dest)
        Logger.success("Downloaded to \(dest)")
    }
}
