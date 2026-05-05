import ArgumentParser
import Foundation

struct AndroidImagesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "images",
        abstract: "Manage Play Store promotional images",
        subcommands: [
            AndroidImagesListCommand.self,
            AndroidImagesUploadCommand.self,
        ]
    )
}

struct AndroidImagesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List uploaded images for a locale")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Language code (e.g. en-US, ja-JP)")
    var language: String = "en-US"

    @Option(name: .long, help: "Image type: featureGraphic | icon | promoGraphic | phoneScreenshots | sevenInchScreenshots | tenInchScreenshots")
    var imageType: String = "featureGraphic"

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Fetching \(imageType) images for \(pkg) [\(language)]")
        let images = try await client.listImages(packageName: pkg, language: language, imageType: imageType)

        if images.isEmpty { Logger.info("No images found"); return }
        Logger.info("\(images.count) image(s)\n")
        for img in images {
            let id  = img["id"] as? String ?? "-"
            let url = img["url"] as? String ?? "-"
            let sha1 = img["sha1"] as? String ?? ""
            print("  id: \(id)  sha1: \(sha1)")
            print("    \(url)")
        }
    }
}

struct AndroidImagesUploadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "upload", abstract: "Upload a promotional image")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Language code (e.g. en-US, ja-JP)")
    var language: String = "en-US"

    @Option(name: .long, help: "Image type: featureGraphic | icon | promoGraphic | phoneScreenshots | sevenInchScreenshots | tenInchScreenshots")
    var imageType: String = "featureGraphic"

    @Option(name: .long, help: "Path to image file (PNG)")
    var image: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        guard FileManager.default.fileExists(atPath: image) else {
            Logger.error("Image not found: \(image)"); Foundation.exit(1)
        }

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Uploading \(imageType) for \(pkg) [\(language)]")
        try await client.uploadImage(packageName: pkg, language: language, imageType: imageType, imagePath: image)
        Logger.success("Image uploaded and published")
    }
}
