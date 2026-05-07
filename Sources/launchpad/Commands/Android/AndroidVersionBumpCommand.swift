import ArgumentParser
import Foundation

struct AndroidVersionBumpCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "version-bump",
        abstract: "Bump the local Android app version in build.gradle",
        subcommands: [
            AndroidVersionBumpVersionCommand.self,
            AndroidVersionBumpCodeCommand.self,
            AndroidVersionBumpShowCommand.self,
        ]
    )
}

// MARK: - show

struct AndroidVersionBumpShowCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "show", abstract: "Show current versionName and versionCode")

    @Option(name: .long, help: "Android project directory [config: android.projectDir]")
    var projectDir: String?

    mutating func run() throws {
        DotEnv.load()
        let cfg = Config.load().android
        let dir = projectDir ?? cfg?.projectDir ?? "./"
        let gradle = try findBuildGradle(in: dir)
        let (name, code) = try readVersions(from: gradle)
        print("  versionName: \(name)")
        print("  versionCode: \(code)")
    }
}

// MARK: - versionName

struct AndroidVersionBumpVersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "version", abstract: "Bump or set versionName (e.g. 1.2.3)")

    @Option(name: .long, help: "Android project directory [config: android.projectDir]")
    var projectDir: String?

    @Flag(name: .long, help: "Increment patch component (1.0.0 → 1.0.1)")
    var patch: Bool = false

    @Flag(name: .long, help: "Increment minor component (1.0.0 → 1.1.0)")
    var minor: Bool = false

    @Flag(name: .long, help: "Increment major component (1.0.0 → 2.0.0)")
    var major: Bool = false

    @Option(name: .long, help: "Set exact version string (e.g. 2.0.0)")
    var set: String?

    mutating func run() throws {
        DotEnv.load()
        let cfg  = Config.load().android
        let dir  = projectDir ?? cfg?.projectDir ?? "./"
        let gradle = try findBuildGradle(in: dir)
        var content = try String(contentsOfFile: gradle, encoding: .utf8)

        let (current, _) = try readVersions(from: gradle)
        let next: String

        if let s = set {
            next = s
        } else if patch || minor || major {
            next = try bumpVersion(current, patch: patch, minor: minor, major: major)
        } else {
            Logger.error("Specify --patch, --minor, --major, or --set <version>")
            Foundation.exit(1)
        }

        content = replaceVersionName(in: content, with: next)
        try content.write(toFile: gradle, atomically: true, encoding: .utf8)
        Logger.success("versionName: \"\(current)\" → \"\(next)\"")
    }
}

// MARK: - versionCode

struct AndroidVersionBumpCodeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "code", abstract: "Increment or set versionCode")

    @Option(name: .long, help: "Android project directory [config: android.projectDir]")
    var projectDir: String?

    @Option(name: .long, help: "Set exact versionCode instead of auto-incrementing")
    var set: Int?

    mutating func run() throws {
        DotEnv.load()
        let cfg  = Config.load().android
        let dir  = projectDir ?? cfg?.projectDir ?? "./"
        let gradle = try findBuildGradle(in: dir)
        var content = try String(contentsOfFile: gradle, encoding: .utf8)

        let (_, currentCode) = try readVersions(from: gradle)
        guard let currentInt = Int(currentCode) else {
            Logger.error("Could not parse versionCode as integer: \(currentCode)")
            Foundation.exit(1)
        }
        let next = set ?? (currentInt + 1)
        content = replaceVersionCode(in: content, with: next)
        try content.write(toFile: gradle, atomically: true, encoding: .utf8)
        Logger.success("versionCode: \(currentInt) → \(next)")
    }
}

// MARK: - helpers

private func findBuildGradle(in dir: String) throws -> String {
    let candidates = [
        "\(dir)/app/build.gradle",
        "\(dir)/app/build.gradle.kts",
        "\(dir)/build.gradle",
    ]
    for path in candidates {
        if FileManager.default.fileExists(atPath: path) {
            let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            if content.contains("versionName") { return path }
        }
    }
    // fallback: search one level deep
    let fm = FileManager.default
    if let items = try? fm.contentsOfDirectory(atPath: dir) {
        for item in items {
            let path = "\(dir)/\(item)/build.gradle"
            if fm.fileExists(atPath: path),
               let content = try? String(contentsOfFile: path, encoding: .utf8),
               content.contains("versionName") {
                return path
            }
        }
    }
    throw LaunchpadError.fileNotFound("build.gradle with versionName not found under \(dir)")
}

private func readVersions(from path: String) throws -> (name: String, code: String) {
    let content = try String(contentsOfFile: path, encoding: .utf8)
    var name = "-"
    var code = "-"
    for line in content.components(separatedBy: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("versionName ") {
            name = t.replacingOccurrences(of: "versionName ", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        } else if t.hasPrefix("versionCode ") {
            code = t.replacingOccurrences(of: "versionCode ", with: "")
                    .trimmingCharacters(in: .whitespaces)
        }
    }
    return (name, code)
}

private func replaceVersionName(in content: String, with version: String) -> String {
    var result = content
    let lines = result.components(separatedBy: "\n")
    let updated = lines.map { line -> String in
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("versionName ") {
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            return "\(indent)versionName \"\(version)\""
        }
        return line
    }
    result = updated.joined(separator: "\n")
    return result
}

private func replaceVersionCode(in content: String, with code: Int) -> String {
    var result = content
    let lines = result.components(separatedBy: "\n")
    let updated = lines.map { line -> String in
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("versionCode ") {
            let indent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
            return "\(indent)versionCode \(code)"
        }
        return line
    }
    result = updated.joined(separator: "\n")
    return result
}

private func bumpVersion(_ version: String, patch: Bool, minor: Bool, major: Bool) throws -> String {
    var parts = version.split(separator: ".").compactMap { Int($0) }
    while parts.count < 3 { parts.append(0) }
    if major {
        parts[0] += 1; parts[1] = 0; parts[2] = 0
    } else if minor {
        parts[1] += 1; parts[2] = 0
    } else {
        parts[2] += 1
    }
    return parts.map(String.init).joined(separator: ".")
}
