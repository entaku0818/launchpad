import Foundation

enum XcodeProject {
    static func versionNumber(project: String, target: String) throws -> String {
        let output = try Shell.run([
            "xcodebuild", "-project", project, "-target", target,
            "-showBuildSettings",
        ])
        return try extract("MARKETING_VERSION", from: output)
    }

    static func buildNumber(project: String, target: String) throws -> String {
        let output = try Shell.run([
            "xcodebuild", "-project", project, "-target", target,
            "-showBuildSettings",
        ])
        return try extract("CURRENT_PROJECT_VERSION", from: output)
    }

    static func incrementBuildNumber(project: String) throws -> String {
        try Shell.run(["xcrun", "agvtool", "next-version", "-all"], cwd: URL(fileURLWithPath: project).deletingLastPathComponent().path)
        let dir = URL(fileURLWithPath: project).deletingLastPathComponent().path
        let output = try Shell.run(["xcrun", "agvtool", "what-version", "-terse"], cwd: dir)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extract(_ key: String, from buildSettings: String) throws -> String {
        for line in buildSettings.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(key) = ") {
                return String(trimmed.dropFirst("\(key) = ".count))
            }
        }
        throw LaunchpadError.fileNotFound("Build setting '\(key)' not found")
    }
}
