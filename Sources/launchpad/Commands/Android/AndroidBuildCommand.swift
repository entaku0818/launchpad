import ArgumentParser
import Foundation

struct AndroidBuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build Android APK or AAB via Gradle"
    )

    @Option(name: .long, help: "Android project directory")
    var projectDir: String = "./"

    @Flag(name: .long, help: "Build release AAB with signing (default: debug APK)")
    var release: Bool = false

    mutating func run() throws {
        if release {
            print("Building release AAB...")
            let env = try signingEnv()
            try Shell.runLive(["./gradlew", "bundleRelease"], env: env, cwd: projectDir)
            print("Release AAB build complete.")
        } else {
            print("Building debug APK...")
            try Shell.runLive(["./gradlew", "assembleDebug"], cwd: projectDir)
            print("Debug APK build complete.")
        }
    }

    private func signingEnv() throws -> [String: String] {
        let keys = [
            "KEYSTORE_PATH",
            "KEYSTORE_STORE_PASSWORD",
            "KEYSTORE_KEY_ALIAS",
            "KEYSTORE_KEY_PASSWORD",
        ]
        let env = ProcessInfo.processInfo.environment
        for key in keys {
            if env[key] == nil {
                throw LaunchpadError.missingEnvironmentVariable(key)
            }
        }
        return [
            "ORG_GRADLE_PROJECT_STORE_FILE": env["KEYSTORE_PATH"]!,
            "ORG_GRADLE_PROJECT_STORE_PASSWORD": env["KEYSTORE_STORE_PASSWORD"]!,
            "ORG_GRADLE_PROJECT_KEY_ALIAS": env["KEYSTORE_KEY_ALIAS"]!,
            "ORG_GRADLE_PROJECT_KEY_PASSWORD": env["KEYSTORE_KEY_PASSWORD"]!,
        ]
    }
}
