import ArgumentParser
import Foundation

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Create .launchpadrc and .env template in current directory"
    )

    mutating func run() throws {
        try writeConfig()
        try writeDotEnvTemplate()
        Logger.success("Created .launchpadrc and .env.template")
        Logger.info("Edit .launchpadrc with your project settings, then copy .env.template to .env and fill in credentials.")
    }

    private func writeConfig() throws {
        let path = ".launchpadrc"
        if FileManager.default.fileExists(atPath: path) {
            Logger.warn(".launchpadrc already exists, skipping.")
            return
        }

        let config = Config(
            ios: Config.iOS(
                project: "ios/App.xcodeproj",
                scheme: "App",
                bundleId: "com.example.app",
                output: "./build",
                exportMethod: "app-store"
            ),
            android: Config.Android(
                projectDir: "android/",
                packageName: "com.example.app"
            )
        )
        try config.save(to: path)
        Logger.info("Created \(path)")
    }

    private func writeDotEnvTemplate() throws {
        let path = ".env.template"
        if FileManager.default.fileExists(atPath: path) {
            Logger.warn(".env.template already exists, skipping.")
            return
        }

        let template = """
        # App Store Connect API Key
        # https://appstoreconnect.apple.com/access/api
        APP_STORE_CONNECT_API_KEY_KEY_ID=
        APP_STORE_CONNECT_API_KEY_ISSUER_ID=
        APP_STORE_CONNECT_API_KEY_CONTENT=

        # Android Keystore
        KEYSTORE_PATH=/path/to/release.keystore
        KEYSTORE_STORE_PASSWORD=
        KEYSTORE_KEY_ALIAS=
        KEYSTORE_KEY_PASSWORD=

        # Google Play (service account JSON as single line)
        GOOGLE_PLAY_SERVICE_ACCOUNT_JSON=
        """
        try template.write(toFile: path, atomically: true, encoding: .utf8)
        Logger.info("Created \(path)")
    }
}
