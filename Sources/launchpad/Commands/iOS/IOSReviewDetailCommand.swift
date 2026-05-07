import ArgumentParser
import Foundation

struct IOSReviewDetailCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "review-detail",
        abstract: "Manage App Review details: reviewer notes, demo account, and contact info",
        subcommands: [
            IOSReviewDetailGetCommand.self,
            IOSReviewDetailUpdateCommand.self,
        ]
    )
}

struct IOSReviewDetailGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Show App Review notes and demo account for a version")

    @Option(name: .long, help: "App Store version ID (from ios versions list)")
    var versionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching review detail for version \(versionID)")
        let detail = try await client.getReviewDetail(versionID: versionID)

        guard let attrs = detail["attributes"] as? [String: Any] else {
            Logger.info("No review detail found — create one with review-detail update")
            return
        }

        let notes         = attrs["notes"] as? String ?? ""
        let demoName      = attrs["demoAccountName"] as? String ?? ""
        let demoRequired  = attrs["demoAccountRequired"] as? Bool ?? false
        let contactFirst  = attrs["contactFirstName"] as? String ?? ""
        let contactLast   = attrs["contactLastName"] as? String ?? ""
        let contactEmail  = attrs["contactEmail"] as? String ?? ""
        let contactPhone  = attrs["contactPhone"] as? String ?? ""

        if !notes.isEmpty        { print("notes:           \(notes)") }
        print("demoRequired:    \(demoRequired)")
        if !demoName.isEmpty     { print("demoAccountName: \(demoName)") }
        if !contactFirst.isEmpty || !contactLast.isEmpty {
            print("contact:         \(contactFirst) \(contactLast)")
        }
        if !contactEmail.isEmpty { print("contactEmail:    \(contactEmail)") }
        if !contactPhone.isEmpty { print("contactPhone:    \(contactPhone)") }
    }
}

struct IOSReviewDetailUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Set reviewer notes, demo account, or contact for a version")

    @Option(name: .long, help: "App Store version ID (from ios versions list)")
    var versionID: String

    @Option(name: .long, help: "Notes for the App Store reviewer")
    var notes: String?

    @Option(name: .long, help: "Demo account username")
    var demoAccountName: String?

    @Option(name: .long, help: "Demo account password")
    var demoAccountPassword: String?

    @Flag(name: .long, help: "Mark that a demo account is required")
    var demoRequired: Bool = false

    @Flag(name: .long, help: "Mark that no demo account is needed")
    var noDemoRequired: Bool = false

    @Option(name: .long, help: "Reviewer contact first name")
    var contactFirstName: String?

    @Option(name: .long, help: "Reviewer contact last name")
    var contactLastName: String?

    @Option(name: .long, help: "Reviewer contact email")
    var contactEmail: String?

    @Option(name: .long, help: "Reviewer contact phone")
    var contactPhone: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        let demoRequiredFlag: Bool? = demoRequired ? true : (noDemoRequired ? false : nil)

        Logger.step("Fetching or creating review detail for version \(versionID)")
        let detailID = try await client.getOrCreateReviewDetail(appStoreVersionID: versionID)

        Logger.step("Updating review detail")
        try await client.updateReviewDetail(
            detailID: detailID,
            notes: notes,
            demoAccountName: demoAccountName,
            demoAccountPassword: demoAccountPassword,
            demoAccountRequired: demoRequiredFlag,
            contactFirstName: contactFirstName,
            contactLastName: contactLastName,
            contactEmail: contactEmail,
            contactPhone: contactPhone
        )
        Logger.success("Review detail updated")
    }
}
