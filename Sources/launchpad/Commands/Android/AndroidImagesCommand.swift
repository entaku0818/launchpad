import ArgumentParser
import Foundation

struct AndroidImagesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "images",
        abstract: "Manage Play Store promotional images",
        subcommands: [
            AndroidImagesListCommand.self,
            AndroidImagesUploadCommand.self,
            AndroidImagesDeleteCommand.self,
            AndroidImagesDeleteAllCommand.self,
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

struct AndroidImagesDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a specific image by ID")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Language code (e.g. en-US)")
    var language: String = "en-US"

    @Option(name: .long, help: "Image type (e.g. featureGraphic)")
    var imageType: String

    @Option(name: .long, help: "Image ID (from images list)")
    var imageID: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Deleting image \(imageID) (\(imageType)) for [\(language)]")
        try await client.deleteImage(packageName: pkg, language: language, imageType: imageType, imageID: imageID)
        Logger.success("Image deleted")
    }
}

struct AndroidImagesDeleteAllCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete-all", abstract: "Delete all images of a given type for a locale")

    @Option(name: .long, help: "Package name [config: android.packageName]")
    var packageName: String?

    @Option(name: .long, help: "Language code (e.g. en-US)")
    var language: String = "en-US"

    @Option(name: .long, help: "Image type (e.g. featureGraphic, phoneScreenshots)")
    var imageType: String

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().android
        let pkg = packageName ?? cfg?.packageName ?? { Logger.error("--package-name or android.packageName required"); Foundation.exit(1) }()

        let client = try GooglePlayClient.fromEnvironment()
        Logger.step("Deleting all \(imageType) images for [\(language)]")
        try await client.deleteAllImages(packageName: pkg, language: language, imageType: imageType)
        Logger.success("All \(imageType) images deleted")
    }
}
