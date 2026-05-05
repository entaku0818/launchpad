import Foundation

struct Config: Codable {
    struct iOS: Codable {
        var project: String?
        var scheme: String?
        var bundleId: String?
        var output: String?
        var exportMethod: String?
    }

    struct Android: Codable {
        var projectDir: String?
        var packageName: String?
    }

    var ios: iOS?
    var android: Android?

    static let fileName = ".launchpadrc"

    static func load() -> Config {
        let paths = [
            FileManager.default.currentDirectoryPath + "/\(fileName)",
            FileManager.default.homeDirectoryForCurrentUser.path + "/\(fileName)",
        ]
        for path in paths {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let config = try? JSONDecoder().decode(Config.self, from: data) {
                return config
            }
        }
        return Config()
    }

    func save(to path: String = fileName) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: path))
    }
}
