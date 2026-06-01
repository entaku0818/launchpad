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
        let javaEnv = validJavaHomeEnv()

        if release {
            Logger.step("Building release AAB")
            let args = try signingArgs()
            try Shell.runLive(["./gradlew", "bundleRelease"] + args, env: javaEnv, cwd: dir)
            Logger.success("Release AAB build complete.")
        } else {
            Logger.step("Building debug APK")
            try Shell.runLive(["./gradlew", "assembleDebug"], env: javaEnv, cwd: dir)
            Logger.success("Debug APK build complete.")
        }
    }

    // Returns a JAVA_HOME override if the current one is missing or invalid
    private func validJavaHomeEnv() -> [String: String] {
        let current = ProcessInfo.processInfo.environment["JAVA_HOME"] ?? ""
        guard current.isEmpty || !FileManager.default.fileExists(atPath: current) else { return [:] }
        // Try common Java 17 locations
        let candidates = [
            "/Users/entaku/Library/Java/JavaVirtualMachines/jbr-17.0.14/Contents/Home",
            "/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home",
            "/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            Logger.info("JAVA_HOME is invalid; using \(path)")
            return ["JAVA_HOME": path]
        }
        return [:]
    }

    private func signingArgs() throws -> [String] {
        let required = ["KEYSTORE_PATH", "KEYSTORE_STORE_PASSWORD", "KEYSTORE_KEY_ALIAS", "KEYSTORE_KEY_PASSWORD"]
        let env = ProcessInfo.processInfo.environment
        for key in required {
            if env[key] == nil { throw LaunchpadError.missingEnvironmentVariable(key) }
        }
        // Pass signing info via android.injected.signing.* properties — works without modifying build.gradle
        return [
            "-Pandroid.injected.signing.store.file=\(env["KEYSTORE_PATH"]!)",
            "-Pandroid.injected.signing.store.password=\(env["KEYSTORE_STORE_PASSWORD"]!)",
            "-Pandroid.injected.signing.key.alias=\(env["KEYSTORE_KEY_ALIAS"]!)",
            "-Pandroid.injected.signing.key.password=\(env["KEYSTORE_KEY_PASSWORD"]!)",
        ]
    }
}
