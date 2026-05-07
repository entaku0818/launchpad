import ArgumentParser
import Foundation

struct ReleaseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Run the full release pipeline (build → upload → submit)"
    )

    @Flag(name: .long, help: "Release iOS only")
    var ios: Bool = false

    @Flag(name: .long, help: "Release Android only")
    var android: Bool = false

    @Flag(name: .long, help: "Skip the build step (use existing artifact)")
    var skipBuild: Bool = false

    @Flag(name: .long, help: "Dry run: print steps without executing")
    var dryRun: Bool = false

    mutating func run() throws {
        DotEnv.load()
        let doIOS     = ios || (!ios && !android)
        let doAndroid = android || (!ios && !android)

        let binary = CommandLine.arguments[0]

        var steps: [(label: String, args: [String])] = []

        if doIOS {
            if !skipBuild {
                steps.append(("iOS build",   [binary, "ios", "build"]))
            }
            steps.append(("iOS upload",  [binary, "ios", "upload"]))
            steps.append(("iOS submit",  [binary, "ios", "submit"]))
        }

        if doAndroid {
            if !skipBuild {
                steps.append(("Android build",   [binary, "android", "build", "--release"]))
            }
            steps.append(("Android upload",  [binary, "android", "upload"]))
            steps.append(("Android promote", [binary, "android", "promote"]))
        }

        Logger.info("Release pipeline (\(steps.count) step(s)):")
        for (i, step) in steps.enumerated() {
            print("  \(i + 1). \(step.label)")
        }
        print("")

        if dryRun {
            Logger.info("Dry run — no commands executed.")
            return
        }

        for step in steps {
            Logger.step(step.label)
            do {
                try Shell.runLive(step.args)
                Logger.success("\(step.label) done")
            } catch {
                Logger.error("\(step.label) failed: \(error.localizedDescription)")
                Logger.info("Resolve the issue and re-run from this step, or use --skip-build to skip the build step.")
                Foundation.exit(1)
            }
            print("")
        }

        Logger.success("Release complete!")
    }
}
