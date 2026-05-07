import ArgumentParser
import Foundation

struct IOSXcodeCloudCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xcode-cloud",
        abstract: "Manage Xcode Cloud CI products, workflows, and build runs",
        subcommands: [
            IOSXcodeCloudProductsCommand.self,
            IOSXcodeCloudWorkflowsCommand.self,
            IOSXcodeCloudBuildsCommand.self,
            IOSXcodeCloudStartCommand.self,
            IOSXcodeCloudArtifactsCommand.self,
            IOSXcodeCloudTestResultsCommand.self,
        ]
    )
}

struct IOSXcodeCloudProductsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "products", abstract: "List Xcode Cloud products for an app")

    @Option(name: .long, help: "App bundle ID [config: ios.bundleId]")
    var bundleID: String?

    mutating func run() async throws {
        DotEnv.load()
        let cfg = Config.load().ios
        let bid = bundleID ?? cfg?.bundleId ?? { Logger.error("--bundle-id required"); Foundation.exit(1) }()

        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        let appID = try await client.findApp(bundleID: bid)
        Logger.step("Fetching Xcode Cloud products for \(bid)")
        let products = try await client.listCIProducts(appID: appID)

        if products.isEmpty { Logger.info("No CI products found"); return }
        Logger.info("\(products.count) product(s)\n")
        for p in products {
            guard let id = p["id"] as? String,
                  let attrs = p["attributes"] as? [String: Any] else { continue }
            let name = attrs["name"] as? String ?? "-"
            print("  \(name)  id: \(id)")
        }
    }
}

struct IOSXcodeCloudWorkflowsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "workflows", abstract: "List workflows for a CI product")

    @Option(name: .long, help: "CI product ID (from xcode-cloud products)")
    var productID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching workflows for product \(productID)")
        let workflows = try await client.listCIWorkflows(productID: productID)

        if workflows.isEmpty { Logger.info("No workflows found"); return }
        Logger.info("\(workflows.count) workflow(s)\n")
        for w in workflows {
            guard let id = w["id"] as? String,
                  let attrs = w["attributes"] as? [String: Any] else { continue }
            let name    = attrs["name"] as? String ?? "-"
            let enabled = attrs["isEnabled"] as? Bool ?? false
            print("  \(name)  enabled: \(enabled)  id: \(id)")
        }
    }
}

struct IOSXcodeCloudBuildsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "builds", abstract: "List recent build runs for a workflow")

    @Option(name: .long, help: "Workflow ID")
    var workflowID: String

    @Option(name: .long, help: "Number of runs to show (default: 10)")
    var limit: Int = 10

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching build runs for workflow \(workflowID)")
        let runs = try await client.listCIBuilds(workflowID: workflowID, limit: limit)

        if runs.isEmpty { Logger.info("No build runs found"); return }
        Logger.info("\(runs.count) run(s)\n")
        for r in runs {
            guard let id = r["id"] as? String,
                  let attrs = r["attributes"] as? [String: Any] else { continue }
            let number    = attrs["number"] as? Int ?? 0
            let state     = attrs["executionProgress"] as? String ?? "-"
            let result    = attrs["completionStatus"] as? String ?? ""
            let createdAt = attrs["createdDate"] as? String ?? "-"
            let icon = result == "SUCCEEDED" ? "✓" : result == "FAILED" ? "✗" : result == "CANCELLED" ? "⊘" : "●"
            print("  \(icon) #\(number) [\(state)\(result.isEmpty ? "" : "/\(result)")] \(createdAt)")
            print("    id: \(id)")
        }
    }
}

struct IOSXcodeCloudStartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "start", abstract: "Start a new CI build run")

    @Option(name: .long, help: "Workflow ID")
    var workflowID: String

    @Option(name: .long, help: "SCM git reference ID (branch or tag)")
    var gitReferenceID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Starting build run for workflow \(workflowID)")
        let runID = try await client.startCIBuild(workflowID: workflowID, gitReferenceID: gitReferenceID)
        Logger.success("Build run started: \(runID)")
    }
}

struct IOSXcodeCloudArtifactsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "artifacts", abstract: "List build artifacts for a CI build run")

    @Option(name: .long, help: "Build run ID")
    var buildRunID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching artifacts for build run \(buildRunID)")
        let artifacts = try await client.listCIArtifacts(buildRunID: buildRunID)

        if artifacts.isEmpty { Logger.info("No artifacts found"); return }
        Logger.info("\(artifacts.count) artifact(s)\n")
        for a in artifacts {
            guard let id = a["id"] as? String,
                  let attrs = a["attributes"] as? [String: Any] else { continue }
            let name      = attrs["fileName"] as? String ?? "-"
            let fileType  = attrs["fileType"] as? String ?? "-"
            let size      = attrs["fileSize"] as? Int ?? 0
            print("  \(name)  [\(fileType)]  \(size / 1024) KB  id: \(id)")
        }
    }
}

struct IOSXcodeCloudTestResultsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "test-results", abstract: "List test results for a CI build run")

    @Option(name: .long, help: "Build run ID")
    var buildRunID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching test results for build run \(buildRunID)")
        let results = try await client.listCITestResults(buildRunID: buildRunID)

        if results.isEmpty { Logger.info("No test results found"); return }
        Logger.info("\(results.count) test result(s)\n")
        for r in results {
            guard let attrs = r["attributes"] as? [String: Any] else { continue }
            let className  = attrs["className"] as? String ?? "-"
            let testName   = attrs["name"] as? String ?? "-"
            let status     = attrs["status"] as? String ?? "-"
            let icon = status == "SUCCESS" ? "✓" : status == "FAILURE" ? "✗" : status == "SKIPPED" ? "⊘" : "●"
            print("  \(icon) \(className).\(testName)  [\(status)]")
        }
    }
}
