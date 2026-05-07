import ArgumentParser
import Foundation

struct IOSNotarizeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notarize",
        abstract: "Submit and manage macOS app notarization (Apple Notarization API v2)",
        subcommands: [
            IOSNotarizeSubmitCommand.self,
            IOSNotarizeStatusCommand.self,
            IOSNotarizeListCommand.self,
            IOSNotarizeLogsCommand.self,
        ]
    )
}

// MARK: - submit

struct IOSNotarizeSubmitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "submit", abstract: "Submit a file for notarization")

    @Option(name: .long, help: "Path to the .dmg, .pkg, or .zip to notarize")
    var file: String

    @Option(name: .long, help: "Submission name shown in the portal (default: filename)")
    var name: String?

    @Flag(name: .long, help: "Wait for notarization to complete (polls every 30s)")
    var wait: Bool = false

    mutating func run() async throws {
        DotEnv.load()
        let client = NotarizationClient(credentials: try ASCCredentials.fromEnvironment())

        let submissionName = name ?? URL(fileURLWithPath: file).lastPathComponent
        Logger.step("Computing SHA-256 and creating submission for '\(submissionName)'")
        let (id, s3Attrs) = try await client.submitForNotarization(filePath: file, submissionName: submissionName)
        Logger.info("Submission ID: \(id)")

        Logger.step("Uploading to Apple S3")
        try await client.uploadToS3(filePath: file, s3Attrs: s3Attrs)
        Logger.success("Upload complete — notarization is in progress")
        Logger.info("Check status with:  launchpad ios notarize status --submission-id \(id)")

        if wait {
            Logger.step("Waiting for result (this can take 1–15 minutes)…")
            var done = false
            while !done {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                let sub = try await client.getSubmission(submissionID: id)
                let status = (sub["attributes"] as? [String: Any])?["status"] as? String ?? "In Progress"
                Logger.info("Status: \(status)")
                if status == "Accepted" || status == "Invalid" || status == "Rejected" {
                    done = true
                    if status == "Accepted" {
                        Logger.success("Notarization accepted — run `xcrun stapler staple <file>` to attach the ticket")
                    } else {
                        Logger.error("Notarization \(status) — run `launchpad ios notarize logs --submission-id \(id)` for details")
                    }
                }
            }
        }
    }
}

// MARK: - status

struct IOSNotarizeStatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "Check notarization status for a submission")

    @Option(name: .long, help: "Submission ID (from notarize submit)")
    var submissionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = NotarizationClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching submission \(submissionID)")
        let sub = try await client.getSubmission(submissionID: submissionID)

        guard let attrs = sub["attributes"] as? [String: Any] else {
            Logger.error("Submission not found"); Foundation.exit(1)
        }

        let name      = attrs["name"] as? String ?? "-"
        let status    = attrs["status"] as? String ?? "-"
        let createdAt = attrs["createdDate"] as? String ?? "-"

        print("\nid:        \(submissionID)")
        print("name:      \(name)")
        print("status:    \(statusIcon(status)) \(status)")
        print("created:   \(createdAt)")
    }

    private func statusIcon(_ s: String) -> String {
        switch s {
        case "Accepted":    return "✓"
        case "Invalid",
             "Rejected":    return "✗"
        case "In Progress": return "⏳"
        default:            return "●"
        }
    }
}

// MARK: - list

struct IOSNotarizeListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List recent notarization submissions")

    @Option(name: .long, help: "Number of submissions to show (default: 10)")
    var limit: Int = 10

    mutating func run() async throws {
        DotEnv.load()
        let client = NotarizationClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching recent notarization submissions")
        let submissions = try await client.listSubmissions(limit: limit)

        if submissions.isEmpty { Logger.info("No submissions found"); return }
        Logger.info("\(submissions.count) submission(s)\n")
        for s in submissions {
            guard let id = s["id"] as? String,
                  let attrs = s["attributes"] as? [String: Any] else { continue }
            let name    = attrs["name"] as? String ?? "-"
            let status  = attrs["status"] as? String ?? "-"
            let created = attrs["createdDate"] as? String ?? "-"
            let icon    = status == "Accepted" ? "✓" : status.contains("Progress") ? "⏳" : "✗"
            print("  \(icon) \(name)  [\(status)]  \(created)")
            print("    id: \(id)\n")
        }
    }
}

// MARK: - logs

struct IOSNotarizeLogsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "logs", abstract: "Show notarization logs for a submission")

    @Option(name: .long, help: "Submission ID (from notarize submit or list)")
    var submissionID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = NotarizationClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching logs for submission \(submissionID)")
        let logs = try await client.getSubmissionLogs(submissionID: submissionID)
        print(logs)
    }
}
