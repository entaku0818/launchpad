import Foundation

enum LaunchpadError: Error, LocalizedError {
    case missingEnvironmentVariable(String)
    case commandFailed(String, Int32)
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .missingEnvironmentVariable(let name):
            return "Missing environment variable: \(name)"
        case .commandFailed(let cmd, let code):
            return "Command failed (\(code)): \(cmd)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}
