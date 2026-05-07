import ArgumentParser
import Foundation

struct ReleaseNotesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release-notes",
        abstract: "Generate release notes from git log and write to metadata files"
    )

    @Option(name: .long, help: "Git ref to start from (e.g. v1.0.0, HEAD~20). Defaults to last tag")
    var from: String?

    @Option(name: .long, help: "Git ref to end at (default: HEAD)")
    var to: String = "HEAD"

    @Option(name: .long, help: "Locale to write to (e.g. ja, en-US). Use 'all' to write to every locale directory found (default: print only)")
    var locale: String?

    @Flag(name: .long, help: "Write to iOS metadata (fastlane/metadata/{locale}/release_notes.txt)")
    var ios: Bool = false

    @Flag(name: .long, help: "Write to Android metadata (fastlane/metadata/android/{locale}/changelogs/default.txt)")
    var android: Bool = false

    @Option(name: .long, help: "Max number of commits to include (default: 20)")
    var limit: Int = 20

    mutating func run() throws {
        let fromRef: String
        if let f = from {
            fromRef = f
        } else {
            // find last git tag
            let lastTag = (try? Shell.run(["git", "describe", "--tags", "--abbrev=0"]))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            fromRef = lastTag.isEmpty ? "" : lastTag
        }

        let range = fromRef.isEmpty ? to : "\(fromRef)..\(to)"
        let log = try Shell.run([
            "git", "log", range,
            "--pretty=format:- %s",
            "--no-merges",
            "--max-count=\(limit)",
        ])

        let notes = log.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.isEmpty {
            Logger.info("No commits found in range \(range)")
            return
        }

        Logger.info("Release notes (\(range)):\n")
        print(notes)
        print("")

        let iosDir     = "fastlane/metadata"
        let androidDir = "fastlane/metadata/android"

        if ios {
            try writeToLocales(notes: notes, baseDir: iosDir, fileName: "release_notes.txt", localeOverride: locale)
        }
        if android {
            try writeToAndroidLocales(notes: notes, baseDir: androidDir, localeOverride: locale)
        }
        if !ios && !android && locale != nil {
            Logger.info("Tip: add --ios and/or --android to write to metadata files.")
        }
    }

    private func writeToLocales(notes: String, baseDir: String, fileName: String, localeOverride: String?) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: baseDir) else {
            Logger.warn("Directory not found: \(baseDir) — skipping iOS write")
            return
        }

        let locales: [String]
        if let l = localeOverride, l != "all" {
            locales = [l]
        } else {
            locales = ((try? fm.contentsOfDirectory(atPath: baseDir)) ?? []).filter {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: "\(baseDir)/\($0)", isDirectory: &isDir)
                return isDir.boolValue && !$0.hasPrefix(".")
            }.sorted()
        }

        var written = 0
        for locale in locales {
            let path = "\(baseDir)/\(locale)/\(fileName)"
            if fm.fileExists(atPath: "\(baseDir)/\(locale)") {
                try notes.write(toFile: path, atomically: true, encoding: .utf8)
                written += 1
            }
        }
        Logger.success("Wrote release_notes.txt to \(written) iOS locale(s)")
    }

    private func writeToAndroidLocales(notes: String, baseDir: String, localeOverride: String?) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: baseDir) else {
            Logger.warn("Directory not found: \(baseDir) — skipping Android write")
            return
        }

        let locales: [String]
        if let l = localeOverride, l != "all" {
            locales = [l]
        } else {
            locales = ((try? fm.contentsOfDirectory(atPath: baseDir)) ?? []).filter {
                var isDir: ObjCBool = false
                fm.fileExists(atPath: "\(baseDir)/\($0)", isDirectory: &isDir)
                return isDir.boolValue && !$0.hasPrefix(".")
            }.sorted()
        }

        // Android changelog max 500 chars
        let truncated = notes.count > 500 ? String(notes.prefix(497)) + "..." : notes

        var written = 0
        for locale in locales {
            let changelogDir = "\(baseDir)/\(locale)/changelogs"
            try fm.createDirectory(atPath: changelogDir, withIntermediateDirectories: true)
            let path = "\(changelogDir)/default.txt"
            try truncated.write(toFile: path, atomically: true, encoding: .utf8)
            written += 1
        }
        Logger.success("Wrote changelogs/default.txt to \(written) Android locale(s)")
        if notes.count > 500 {
            Logger.warn("Release notes truncated to 500 chars for Android (was \(notes.count) chars)")
        }
    }
}
