import Foundation

enum LaunchpadError: Error, LocalizedError {
    case missingEnvironmentVariable(String)
    case commandFailed(String, Int32)
    case fileNotFound(String)
    case appNotFound(String)
    case versionNotFound(String)
    case buildNotFound
    case apiError(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingEnvironmentVariable(let name):
            return "Missing environment variable: \(name)"
        case .commandFailed(let cmd, let code):
            return "Command failed (exit \(code)): \(cmd)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .appNotFound(let bundleID):
            return "App not found on ASC: \(bundleID)"
        case .versionNotFound(let version):
            return "App Store version not found: \(version)"
        case .buildNotFound:
            return "No build found on ASC"
        case .apiError(let code, let body):
            return "ASC API error \(code): \(body)"
        case .invalidResponse:
            return "Invalid API response"
        }
    }
}
