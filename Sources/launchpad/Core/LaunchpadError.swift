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
            return """
            Missing required environment variable: \(name)
            Set it in your .env file or export it in your shell before running this command.
            Run `launchpad init` to generate an .env template with all required variables.
            """
        case .commandFailed(let cmd, let code):
            return "Command exited with code \(code): \(cmd)"
        case .fileNotFound(let path):
            return "File not found: \(path)\nCheck that the path is correct and the file exists."
        case .appNotFound(let bundleID):
            return """
            App not found for bundle ID '\(bundleID)'.
            Verify the bundle ID is correct and the app exists in App Store Connect.
            """
        case .versionNotFound(let version):
            return """
            Version '\(version)' not found in App Store Connect.
            Make sure this version exists and is in an editable state (e.g. Prepare for Submission).
            """
        case .buildNotFound:
            return """
            No processed build found in App Store Connect.
            Upload a build first with `launchpad ios upload`, then wait for processing to complete.
            """
        case .apiError(let code, let body):
            return formatAPIError(code: code, body: body)
        case .invalidResponse:
            return "Unexpected response format from the API. The API may have returned an error without a proper status code."
        }
    }
}

private func formatAPIError(code: Int, body: String) -> String {
    if let data = body.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let errors = json["errors"] as? [[String: Any]],
       let first = errors.first {
        let title  = first["title"] as? String ?? ""
        let detail = first["detail"] as? String ?? ""
        let apiCode = first["code"] as? String ?? ""
        var msg = "API error \(code)"
        if !apiCode.isEmpty { msg += " [\(apiCode)]" }
        if !title.isEmpty   { msg += ": \(title)" }
        if !detail.isEmpty  { msg += "\n\(detail)" }
        if let meta = first["meta"] as? [String: Any],
           let associated = meta["associatedErrors"] as? [String: Any] {
            for (key, val) in associated {
                if let errs = val as? [[String: Any]] {
                    for e in errs {
                        let aTitle  = e["title"] as? String ?? ""
                        let aDetail = e["detail"] as? String ?? ""
                        msg += "\n  [\(key)] \(aTitle): \(aDetail)"
                    }
                }
            }
        }
        return msg
    }
    // Search Ads / other APIs may use a different shape
    if let data = body.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let error = json["error"] as? [String: Any] {
        let msg = error["message"] as? String ?? body
        return "API error \(code): \(msg)"
    }
    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "API error \(code)" : "API error \(code): \(trimmed)"
}
