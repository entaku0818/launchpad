import Foundation

enum Shell {
    @discardableResult
    static func run(_ args: [String], env: [String: String] = [:], cwd: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args

        var environment = ProcessInfo.processInfo.environment
        env.forEach { environment[$0] = $1 }
        process.environment = environment

        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            print(err)
            throw LaunchpadError.commandFailed(args.joined(separator: " "), process.terminationStatus)
        }
        return out
    }

    // Like run() but merges stderr into the returned string (useful when a process exits 0 on failure)
    @discardableResult
    static func runCombined(_ args: [String], env: [String: String] = [:], cwd: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args

        var environment = ProcessInfo.processInfo.environment
        env.forEach { environment[$0] = $1 }
        process.environment = environment

        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let combined = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            print(combined)
            throw LaunchpadError.commandFailed(args.joined(separator: " "), process.terminationStatus)
        }
        return combined
    }

    static func runLive(_ args: [String], env: [String: String] = [:], cwd: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args

        var environment = ProcessInfo.processInfo.environment
        env.forEach { environment[$0] = $1 }
        process.environment = environment

        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw LaunchpadError.commandFailed(args.joined(separator: " "), process.terminationStatus)
        }
    }
}
