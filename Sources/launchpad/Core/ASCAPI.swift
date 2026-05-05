import Foundation

struct ASCAPIClient {
    private let credentials: ASCCredentials
    private let baseURL = "https://api.appstoreconnect.apple.com/v1"

    init(credentials: ASCCredentials) {
        self.credentials = credentials
    }

    // MARK: - Apps

    func findApp(bundleID: String) async throws -> String {
        let data = try await get("/apps?filter[bundleId]=\(bundleID)&fields[apps]=id,name")
        guard
            let apps = data["data"] as? [[String: Any]],
            let id = apps.first?["id"] as? String
        else {
            throw LaunchpadError.appNotFound(bundleID)
        }
        return id
    }

    // MARK: - App Store Versions

    func getAppStoreVersion(appID: String, version: String) async throws -> String {
        let encoded = version.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? version
        let data = try await get(
            "/apps/\(appID)/appStoreVersions?filter[platform]=IOS&filter[versionString]=\(encoded)&filter[appStoreState]=PREPARE_FOR_SUBMISSION"
        )
        guard
            let versions = data["data"] as? [[String: Any]],
            let id = versions.first?["id"] as? String
        else {
            throw LaunchpadError.versionNotFound(version)
        }
        return id
    }

    // MARK: - Localizations (metadata)

    func getLocalizations(versionID: String) async throws -> [[String: Any]] {
        let data = try await get("/appStoreVersions/\(versionID)/appStoreVersionLocalizations")
        return data["data"] as? [[String: Any]] ?? []
    }

    func updateLocalization(localizationID: String, attributes: [String: Any]) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "appStoreVersionLocalizations",
                "id": localizationID,
                "attributes": attributes,
            ]
        ]
        _ = try await patch("/appStoreVersionLocalizations/\(localizationID)", body: body)
    }

    // MARK: - Screenshots

    func getScreenshotSets(localizationID: String) async throws -> [[String: Any]] {
        let data = try await get("/appStoreVersionLocalizations/\(localizationID)/appScreenshotSets")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getScreenshots(setID: String) async throws -> [[String: Any]] {
        let data = try await get("/appScreenshotSets/\(setID)/appScreenshots")
        return data["data"] as? [[String: Any]] ?? []
    }

    func deleteScreenshot(id: String) async throws {
        try await delete("/appScreenshots/\(id)")
    }

    func reserveScreenshot(setID: String, fileName: String, fileSize: Int) async throws -> (id: String, uploadURL: String) {
        let body: [String: Any] = [
            "data": [
                "type": "appScreenshots",
                "attributes": ["fileName": fileName, "fileSize": fileSize],
                "relationships": [
                    "appScreenshotSet": ["data": ["type": "appScreenshotSets", "id": setID]]
                ],
            ]
        ]
        let response = try await post("/appScreenshots", body: body)
        guard
            let dataDict = response["data"] as? [String: Any],
            let id = dataDict["id"] as? String,
            let attrs = dataDict["attributes"] as? [String: Any],
            let ops = attrs["uploadOperations"] as? [[String: Any]],
            let url = ops.first?["url"] as? String
        else {
            throw LaunchpadError.invalidResponse
        }
        return (id, url)
    }

    func commitScreenshot(id: String, md5: String, fileSize: Int) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "appScreenshots",
                "id": id,
                "attributes": [
                    "uploaded": true,
                    "sourceFileChecksum": md5,
                ],
            ]
        ]
        _ = try await patch("/appScreenshots/\(id)", body: body)
    }

    // MARK: - Submit for Review

    func submitForReview(versionID: String) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "appStoreVersionSubmissions",
                "relationships": [
                    "appStoreVersion": [
                        "data": ["type": "appStoreVersions", "id": versionID]
                    ]
                ],
            ]
        ]
        _ = try await post("/appStoreVersionSubmissions", body: body)
    }

    // MARK: - Build

    func getLatestBuild(appID: String) async throws -> String {
        let data = try await get("/builds?filter[app]=\(appID)&sort=-uploadedDate&limit=1")
        guard
            let builds = data["data"] as? [[String: Any]],
            let id = builds.first?["id"] as? String
        else {
            throw LaunchpadError.buildNotFound
        }
        return id
    }

    func setBuildForVersion(versionID: String, buildID: String) async throws {
        let body: [String: Any] = ["data": ["type": "builds", "id": buildID]]
        _ = try await patch("/appStoreVersions/\(versionID)/relationships/build", body: body)
    }

    // MARK: - HTTP

    private func get(_ path: String) async throws -> [String: Any] {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try credentials.generateJWT())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response, data)
        return try parseJSON(data)
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        try await send("POST", path: path, body: body)
    }

    private func patch(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        try await send("PATCH", path: path, body: body)
    }

    private func delete(_ path: String) async throws {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(try credentials.generateJWT())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response, data)
    }

    private func send(_ method: String, path: String, body: [String: Any]) async throws -> [String: Any] {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try credentials.generateJWT())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response, data)
        return (try? parseJSON(data)) ?? [:]
    }

    private func checkStatus(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LaunchpadError.apiError(http.statusCode, body)
        }
    }

    private func parseJSON(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }
}
