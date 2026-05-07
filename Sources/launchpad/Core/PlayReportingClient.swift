import Foundation

struct PlayReportingClient {
    private let baseURL = "https://playdeveloperreporting.googleapis.com/v1beta1"
    private let googlePlayClient: GooglePlayClient

    init(googlePlayClient: GooglePlayClient) {
        self.googlePlayClient = googlePlayClient
    }

    static func fromEnvironment() throws -> PlayReportingClient {
        let play = try GooglePlayClient.fromEnvironment()
        return PlayReportingClient(googlePlayClient: play)
    }

    // MARK: - Metric Sets

    func queryCrashRate(packageName: String, days: Int = 7) async throws -> [String: Any] {
        return try await queryMetricSet(
            resource: "apps/\(packageName)/crashRateMetricSet",
            metrics: ["crashRate", "distinctUsers"],
            days: days
        )
    }

    func queryANRRate(packageName: String, days: Int = 7) async throws -> [String: Any] {
        return try await queryMetricSet(
            resource: "apps/\(packageName)/anrRateMetricSet",
            metrics: ["anrRate", "distinctUsers"],
            days: days
        )
    }

    func querySlowStartRate(packageName: String, days: Int = 7) async throws -> [String: Any] {
        return try await queryMetricSet(
            resource: "apps/\(packageName)/slowStartRateMetricSet",
            metrics: ["slowStartRate", "distinctUsers"],
            days: days
        )
    }

    func querySlowRenderingRate(packageName: String, days: Int = 7) async throws -> [String: Any] {
        return try await queryMetricSet(
            resource: "apps/\(packageName)/slowRenderingRateMetricSet",
            metrics: ["slowRenderingRate", "distinctUsers"],
            days: days
        )
    }

    func queryExcessiveWakeupRate(packageName: String, days: Int = 7) async throws -> [String: Any] {
        return try await queryMetricSet(
            resource: "apps/\(packageName)/excessiveWakeupRateMetricSet",
            metrics: ["excessiveWakeupRate", "distinctUsers"],
            days: days
        )
    }

    func queryStuckWakelockRate(packageName: String, days: Int = 7) async throws -> [String: Any] {
        return try await queryMetricSet(
            resource: "apps/\(packageName)/stuckBackgroundWakelockRateMetricSet",
            metrics: ["stuckBgWakelockRate", "distinctUsers"],
            days: days
        )
    }

    func listAnomalies(packageName: String) async throws -> [[String: Any]] {
        let json = try await get("/apps/\(packageName)/anomalies?pageSize=50")
        return json["anomalies"] as? [[String: Any]] ?? []
    }

    // MARK: - Private

    private func queryMetricSet(resource: String, metrics: [String], days: Int) async throws -> [String: Any] {
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let startDate = cal.date(byAdding: .day, value: -days, to: now)!
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "UTC")

        let start = df.string(from: startDate)
        let end   = df.string(from: now)

        let startComponents = start.split(separator: "-").map { Int($0)! }
        let endComponents   = end.split(separator: "-").map { Int($0)! }

        let body: [String: Any] = [
            "timeline": [
                "aggregationPeriod": "DAILY",
                "startDate": ["year": startComponents[0], "month": startComponents[1], "day": startComponents[2]],
                "endDate":   ["year": endComponents[0],   "month": endComponents[1],   "day": endComponents[2]],
            ],
            "metrics": metrics,
            "pageSize": 100,
        ]
        return try await post("/\(resource):query", body: body)
    }

    private func get(_ path: String) async throws -> [String: Any] {
        let token = try await googlePlayClient.accessToken()
        let url = URL(string: baseURL + path)!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        let token = try await googlePlayClient.accessToken()
        let url = URL(string: baseURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }
}
