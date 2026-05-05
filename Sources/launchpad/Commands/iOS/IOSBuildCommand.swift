import ArgumentParser
import Foundation

struct IOSBuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build and archive iOS app"
    )

    @Option(name: .long, help: "Xcode project path (.xcodeproj) [config: ios.project]")
    var project: String?

    @Option(name: .long, help: "Build scheme [config: ios.scheme]")
    var scheme: String?

    @Option(name: .long, help: "Output directory [config: ios.output]")
    var output: String?

    @Option(name: .long, help: "Export method (app-store, ad-hoc, development) [config: ios.exportMethod]")
    var exportMethod: String?

    mutating func run() throws {
        DotEnv.load()
        let cfg = Config.load().ios

        let proj = project ?? cfg?.project ?? { fatalMissing("--project or ios.project in .launchpadrc") }()
        let sch  = scheme  ?? cfg?.scheme  ?? { fatalMissing("--scheme or ios.scheme in .launchpadrc") }()
        let out  = output  ?? cfg?.output  ?? "./build"
        let method = exportMethod ?? cfg?.exportMethod ?? "app-store"

        let archivePath = "\(out)/\(sch).xcarchive"
        let exportPath  = "\(out)/export"
        let exportPlist = try writeExportPlist(method)
        defer { try? FileManager.default.removeItem(atPath: exportPlist) }

        Logger.step("Archiving \(sch)")
        try Shell.runLive([
            "xcodebuild", "archive",
            "-project", proj,
            "-scheme", sch,
            "-archivePath", archivePath,
            "-destination", "generic/platform=iOS",
            "CODE_SIGN_STYLE=Automatic",
        ])

        Logger.step("Exporting IPA")
        try Shell.runLive([
            "xcodebuild", "-exportArchive",
            "-archivePath", archivePath,
            "-exportPath", exportPath,
            "-exportOptionsPlist", exportPlist,
        ])

        Logger.success("Build complete: \(exportPath)/\(sch).ipa")
    }

    private func writeExportPlist(_ method: String) throws -> String {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>method</key>
            <string>\(method)</string>
            <key>signingStyle</key>
            <string>automatic</string>
        </dict>
        </plist>
        """
        let path = NSTemporaryDirectory() + "ExportOptions_\(UUID().uuidString).plist"
        try plist.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }
}

private func fatalMissing(_ msg: String) -> Never {
    Logger.error(msg)
    Foundation.exit(1)
}
