import ArgumentParser
import Foundation

struct IOSSubscriptionImagesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "subscription-images",
        abstract: "Manage images for auto-renewable subscription products",
        subcommands: [
            IOSSubscriptionImagesListCommand.self,
            IOSSubscriptionImagesUploadCommand.self,
            IOSSubscriptionImagesDeleteCommand.self,
        ]
    )
}

struct IOSSubscriptionImagesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List images for a subscription")

    @Option(name: .long, help: "Subscription ID (from subscription-groups products)")
    var subscriptionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching images for subscription \(subscriptionID)")
        let images = try await client.listSubscriptionImages(subscriptionID: subscriptionID)

        if images.isEmpty { Logger.info("No subscription images found"); return }
        Logger.info("\(images.count) image(s)\n")
        for img in images {
            guard let id = img["id"] as? String,
                  let attrs = img["attributes"] as? [String: Any] else { continue }
            let name  = attrs["fileName"] as? String ?? "-"
            let state = (attrs["assetDeliveryState"] as? [String: Any])?["state"] as? String ?? "-"
            print("  \(name)  [\(state)]  id: \(id)")
        }
    }
}

struct IOSSubscriptionImagesUploadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "upload", abstract: "Upload an image for a subscription")

    @Option(name: .long, help: "Subscription ID (from subscription-groups products)")
    var subscriptionID: String

    @Option(name: .long, help: "Path to image file (PNG, 1024×1024 recommended)")
    var file: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Uploading subscription image from \(file)")
        let id = try await client.createSubscriptionImage(subscriptionID: subscriptionID, filePath: file)
        Logger.success("Subscription image uploaded: \(id)")
    }
}

struct IOSSubscriptionImagesDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a subscription image")

    @Option(name: .long, help: "Subscription image ID (from list)")
    var imageID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting subscription image \(imageID)")
        try await client.deleteSubscriptionImage(imageID: imageID)
        Logger.success("Subscription image deleted")
    }
}
