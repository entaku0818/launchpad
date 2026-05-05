import ArgumentParser
import Foundation

struct IOSBuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build and archive iOS app"
    )

    @Option(name: .long, help: "Xcode project path (.xcodeproj)")
    var project: String

    @Option(name: .long, help: "Build scheme")
    var scheme: String

    @Option(name: .long, help: "Output directory for archive and IPA")
    var output: String = "./build"

    @Option(name: .long, help: "Export method (app-store, ad-hoc, development)")
    var exportMethod: String = "app-store"

    mutating func run() throws {
        let archivePath = "\(output)/\(scheme).xcarchive"
        let exportPath = "\(output)/export"
        let exportPlist = try writeExportPlist(exportMethod: exportMethod)
        defer { try? FileManager.default.removeItem(atPath: exportPlist) }

        print("Archiving \(scheme)...")
        try Shell.runLive([
            "xcodebuild", "archive",
            "-project", project,
            "-scheme", scheme,
            "-archivePath", archivePath,
            "-destination", "generic/platform=iOS",
            "CODE_SIGN_STYLE=Automatic",
        ])

        print("Exporting IPA...")
        try Shell.runLive([
            "xcodebuild", "-exportArchive",
            "-archivePath", archivePath,
            "-exportPath", exportPath,
            "-exportOptionsPlist", exportPlist,
        ])

        let ipaPath = "\(exportPath)/\(scheme).ipa"
        print("Build complete: \(ipaPath)")
    }

    private func writeExportPlist(exportMethod: String) throws -> String {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>method</key>
            <string>\(exportMethod)</string>
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
