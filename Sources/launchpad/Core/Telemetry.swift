import Foundation

// Written once at startup, read from atexit (C context) — nonisolated(unsafe) is intentional
nonisolated(unsafe) private var _command: String = ""
nonisolated(unsafe) private var _start: Date = Date()
nonisolated(unsafe) private var _success: Bool = false

enum Telemetry {
    static func setup(command: String) {
        _command = command
        _start = Date()
        atexit(_fire)
    }

    static func markSuccess() {
        _success = true
    }
}

// Top-level C-compatible function for atexit
private func _fire() {
    // Read URL here so DotEnv.load() (called inside run()) has already executed
    guard let urlStr = ProcessInfo.processInfo.environment["LAUNCHPAD_TELEMETRY_URL"],
          let url = URL(string: urlStr) else { return }

    let duration = Int(Date().timeIntervalSince(_start) * 1000)
    let payload: [String: Any] = [
        "command": _command,
        "success": _success,
        "duration_ms": duration,
        "timestamp": ISO8601DateFormatter().string(from: _start),
        "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
    ]
    guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

    var req = URLRequest(url: url, timeoutInterval: 3)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token = ProcessInfo.processInfo.environment["LAUNCHPAD_TELEMETRY_TOKEN"] {
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    req.httpBody = body

    // Synchronous send — atexit cannot use async/await
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { _, _, _ in sem.signal() }.resume()
    _ = sem.wait(timeout: .now() + 3)
}
