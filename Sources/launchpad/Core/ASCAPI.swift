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
        let data = try await get(
            "/apps/\(appID)/appStoreVersions?filter[platform]=IOS&filter[versionString]=\(version)&filter[appStoreState]=PREPARE_FOR_SUBMISSION"
        )
        guard
            let versions = data["data"] as? [[String: Any]],
            let id = versions.first?["id"] as? String
        else {
            throw LaunchpadError.versionNotFound(version)
        }
        return id
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
                ]
            ]
        ]
        _ = try await post("/appStoreVersionSubmissions", body: body)
        print("Submitted for review successfully.")
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
        let body: [String: Any] = [
            "data": ["type": "builds", "id": buildID]
        ]
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
