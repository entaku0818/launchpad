import ArgumentParser
import Foundation

@main
@available(macOS 13, *)
struct Launchpad: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launchpad",
        abstract: "Personal iOS/Android release tool",
        subcommands: [InitCommand.self, IOSCommand.self, AndroidCommand.self, ReleaseNotesCommand.self, ReleaseCommand.self, DoctorCommand.self]
    )

    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.prefix(while: { !$0.hasPrefix("-") }).joined(separator: " ")
        Telemetry.setup(command: command.isEmpty ? "launchpad" : command)

        do {
            var root = try parseAsRoot()
            if var asyncCmd = root as? AsyncParsableCommand {
                try await asyncCmd.run()
            } else {
                try root.run()
            }
            Telemetry.markSuccess()
            Foundation.exit(0)
        } catch {
            Launchpad.exit(withError: error)
        }
    }
}
