import ArgumentParser
import Foundation

struct IOSReviewAttachmentsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review-attachments",
        abstract: "List App Review supplementary attachments for an App Store version",
        subcommands: [
            IOSReviewAttachmentsListCommand.self,
        ]
    )
}

struct IOSReviewAttachmentsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List review attachments for an App Store version")

    @Option(name: .long, help: "App Store version ID (from ios versions list)")
    var versionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching review attachments for version \(versionID)")
        let attachments = try await client.listReviewAttachments(appStoreVersionID: versionID)

        if attachments.isEmpty { Logger.info("No review attachments found"); return }
        Logger.info("\(attachments.count) attachment(s)\n")
        for a in attachments {
            guard let id = a["id"] as? String,
                  let attrs = a["attributes"] as? [String: Any] else { continue }
            let name     = attrs["fileName"] as? String ?? "-"
            let fileType = attrs["fileType"] as? String ?? "-"
            let uploaded = attrs["uploadOperations"] != nil ? "pending" : "complete"
            print("  \(name)  [\(fileType)]  status: \(uploaded)  id: \(id)")
        }
    }
}
