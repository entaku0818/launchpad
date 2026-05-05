import Foundation

enum Logger {
    private static let isColorEnabled = ProcessInfo.processInfo.environment["NO_COLOR"] == nil

    static func success(_ msg: String) { print(color("  \(msg)", code: "32")) }
    static func info(_ msg: String)    { print(color("→ \(msg)", code: "36")) }
    static func warn(_ msg: String)    { print(color("⚠ \(msg)", code: "33")) }
    static func error(_ msg: String)   { print(color("✗ \(msg)", code: "31")) }
    static func step(_ msg: String)    { print(color("\n● \(msg)", code: "1")) }

    private static func color(_ text: String, code: String) -> String {
        guard isColorEnabled else { return text }
        return "\u{001B}[\(code)m\(text)\u{001B}[0m"
    }
}
