import ArgumentParser
import Foundation

struct AndroidBuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build Android APK or AAB via Gradle"
    )

    @Option(name: .long, help: "Android project directory [config: android.projectDir]")
    var projectDir: String?

    @Flag(name: .long, help: "Build release AAB with signing (default: debug APK)")
    var release: Bool = false

    mutating func run() throws {
        DotEnv.load()
        let cfg = Config.load().android
        let dir = projectDir ?? cfg?.projectDir ?? "./"

        if release {
            Logger.step("Building release AAB")
            let env = try signingEnv()
            try Shell.runLive(["./gradlew", "bundleRelease"], env: env, cwd: dir)
            Logger.success("Release AAB build complete.")
        } else {
            Logger.step("Building debug APK")
            try Shell.runLive(["./gradlew", "assembleDebug"], cwd: dir)
            Logger.success("Debug APK build complete.")
        }
    }

    private func signingEnv() throws -> [String: String] {
        let required = ["KEYSTORE_PATH", "KEYSTORE_STORE_PASSWORD", "KEYSTORE_KEY_ALIAS", "KEYSTORE_KEY_PASSWORD"]
        let env = ProcessInfo.processInfo.environment
        for key in required {
            if env[key] == nil { throw LaunchpadError.missingEnvironmentVariable(key) }
        }
        return [
            "ORG_GRADLE_PROJECT_STORE_FILE":     env["KEYSTORE_PATH"]!,
            "ORG_GRADLE_PROJECT_STORE_PASSWORD": env["KEYSTORE_STORE_PASSWORD"]!,
            "ORG_GRADLE_PROJECT_KEY_ALIAS":      env["KEYSTORE_KEY_ALIAS"]!,
            "ORG_GRADLE_PROJECT_KEY_PASSWORD":   env["KEYSTORE_KEY_PASSWORD"]!,
        ]
    }
}
