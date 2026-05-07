import CryptoKit
import Foundation

struct SearchAdsCredentials {
    let clientID: String
    let teamID: String
    let keyID: String
    let keyContent: String

    static func fromEnvironment() throws -> SearchAdsCredentials {
        guard
            let clientID   = ProcessInfo.processInfo.environment["SEARCH_ADS_CLIENT_ID"],
            let teamID     = ProcessInfo.processInfo.environment["SEARCH_ADS_TEAM_ID"],
            let keyID      = ProcessInfo.processInfo.environment["SEARCH_ADS_KEY_ID"],
            let keyContent = ProcessInfo.processInfo.environment["SEARCH_ADS_PRIVATE_KEY_CONTENT"]
        else {
            throw LaunchpadError.missingEnvironmentVariable(
                "SEARCH_ADS_CLIENT_ID / SEARCH_ADS_TEAM_ID / SEARCH_ADS_KEY_ID / SEARCH_ADS_PRIVATE_KEY_CONTENT"
            )
        }
        return SearchAdsCredentials(clientID: clientID, teamID: teamID, keyID: keyID, keyContent: keyContent)
    }
}

struct SearchAdsClient {
    private let credentials: SearchAdsCredentials
    private let orgID: String?
    private let baseURL = "https://api.searchads.apple.com/api/v5"

    init(credentials: SearchAdsCredentials, orgID: String? = nil) {
        self.credentials = credentials
        self.orgID = orgID ?? ProcessInfo.processInfo.environment["SEARCH_ADS_ORG_ID"]
    }

    // MARK: - Campaigns

    func listCampaigns(limit: Int = 20) async throws -> [[String: Any]] {
        let json = try await get("/campaigns?limit=\(limit)")
        return json["data"] as? [[String: Any]] ?? []
    }

    func getCampaign(campaignID: Int) async throws -> [String: Any] {
        let json = try await get("/campaigns/\(campaignID)")
        return json["data"] as? [String: Any] ?? [:]
    }

    func createCampaign(name: String, appAdamID: Int, budgetAmount: String, currency: String, countryCodes: [String]) async throws -> Int {
        let body: [String: Any] = [
            "name": name,
            "budgetAmount": ["amount": budgetAmount, "currency": currency],
            "dailyBudgetAmount": ["amount": budgetAmount, "currency": currency],
            "adamId": appAdamID,
            "countriesOrRegions": countryCodes,
            "status": "ENABLED",
            "budgetOrders": [],
        ]
        let json = try await post("/campaigns", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? Int else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func updateCampaign(campaignID: Int, name: String?, status: String?, budgetAmount: String?, currency: String?) async throws {
        var body: [String: Any] = [:]
        if let n = name   { body["name"] = n }
        if let s = status { body["status"] = s }
        if let amt = budgetAmount, let cur = currency {
            body["budgetAmount"] = ["amount": amt, "currency": cur]
        }
        _ = try await put("/campaigns/\(campaignID)", body: body)
    }

    func deleteCampaign(campaignID: Int) async throws {
        try await delete("/campaigns/\(campaignID)")
    }

    // MARK: - Ad Groups

    func listAdGroups(campaignID: Int) async throws -> [[String: Any]] {
        let json = try await get("/campaigns/\(campaignID)/adgroups?limit=100")
        return json["data"] as? [[String: Any]] ?? []
    }

    func createAdGroup(campaignID: Int, name: String, cpcBidAmount: String, currency: String, startTime: String, endTime: String?) async throws -> Int {
        var body: [String: Any] = [
            "name": name,
            "campaignId": campaignID,
            "cpcBidAmount": ["amount": cpcBidAmount, "currency": currency],
            "startTime": startTime,
            "status": "ENABLED",
            "automatedKeywordsOptIn": false,
        ]
        if let end = endTime { body["endTime"] = end }
        let json = try await post("/campaigns/\(campaignID)/adgroups", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? Int else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteAdGroup(campaignID: Int, adGroupID: Int) async throws {
        try await delete("/campaigns/\(campaignID)/adgroups/\(adGroupID)")
    }

    // MARK: - Keywords

    func listKeywords(campaignID: Int, adGroupID: Int) async throws -> [[String: Any]] {
        let json = try await get("/campaigns/\(campaignID)/adgroups/\(adGroupID)/keywords?limit=200")
        return json["data"] as? [[String: Any]] ?? []
    }

    func addKeywords(campaignID: Int, adGroupID: Int, keywords: [(text: String, matchType: String, bidAmount: String?, currency: String?)]) async throws -> [[String: Any]] {
        let items: [[String: Any]] = keywords.map { kw in
            var k: [String: Any] = ["text": kw.text, "matchType": kw.matchType, "status": "ACTIVE"]
            if let amt = kw.bidAmount, let cur = kw.currency {
                k["bidAmount"] = ["amount": amt, "currency": cur]
            }
            return k
        }
        let json = try await postArray("/campaigns/\(campaignID)/adgroups/\(adGroupID)/keywords/bulk", body: items)
        return json["data"] as? [[String: Any]] ?? []
    }

    func deleteKeyword(campaignID: Int, adGroupID: Int, keywordID: Int) async throws {
        try await delete("/campaigns/\(campaignID)/adgroups/\(adGroupID)/keywords/\(keywordID)")
    }

    // MARK: - Negative Keywords

    func listNegativeKeywords(campaignID: Int) async throws -> [[String: Any]] {
        let json = try await get("/campaigns/\(campaignID)/negativekeywords?limit=200")
        return json["data"] as? [[String: Any]] ?? []
    }

    func addNegativeKeywords(campaignID: Int, keywords: [(text: String, matchType: String)]) async throws -> [[String: Any]] {
        let items: [[String: Any]] = keywords.map { ["text": $0.text, "matchType": $0.matchType, "status": "ACTIVE"] }
        let json = try await postArray("/campaigns/\(campaignID)/negativekeywords/bulk", body: items)
        return json["data"] as? [[String: Any]] ?? []
    }

    // MARK: - Reports

    func reportCampaigns(startDate: String, endDate: String, granularity: String = "DAILY") async throws -> [String: Any] {
        let body: [String: Any] = [
            "startTime": startDate,
            "endTime": endDate,
            "selector": ["orderBy": [["field": "localSpend", "sortOrder": "DESCENDING"]], "pagination": ["offset": 0, "limit": 100]],
            "groupBy": ["COUNTRY_OR_REGION"],
            "timeZone": "UTC",
            "granularity": granularity,
            "returnRowTotals": true,
            "returnGrandTotals": true,
        ]
        return try await post("/reports/campaigns", body: body)
    }

    func reportKeywords(campaignID: Int, startDate: String, endDate: String) async throws -> [String: Any] {
        let body: [String: Any] = [
            "startTime": startDate,
            "endTime": endDate,
            "selector": [
                "conditions": [["field": "campaignId", "operator": "EQUALS", "values": ["\(campaignID)"]]],
                "orderBy": [["field": "localSpend", "sortOrder": "DESCENDING"]],
                "pagination": ["offset": 0, "limit": 200],
            ],
            "timeZone": "UTC",
            "granularity": "DAILY",
            "returnRowTotals": true,
            "returnGrandTotals": true,
        ]
        return try await post("/reports/keywords", body: body)
    }

    func reportAdGroups(campaignID: Int, startDate: String, endDate: String) async throws -> [String: Any] {
        let body: [String: Any] = [
            "startTime": startDate,
            "endTime": endDate,
            "selector": [
                "conditions": [["field": "campaignId", "operator": "EQUALS", "values": ["\(campaignID)"]]],
                "orderBy": [["field": "localSpend", "sortOrder": "DESCENDING"]],
                "pagination": ["offset": 0, "limit": 100],
            ],
            "timeZone": "UTC",
            "granularity": "DAILY",
            "returnRowTotals": true,
            "returnGrandTotals": true,
        ]
        return try await post("/reports/adgroups", body: body)
    }

    // MARK: - Budget Orders

    func listBudgetOrders() async throws -> [[String: Any]] {
        let json = try await get("/budgetorders?limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    // MARK: - OAuth2 token

    private func accessToken() async throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let exp = now + 60 * 60 * 24 * 180

        let header = jsonBase64url(["alg": "ES256", "kid": credentials.keyID, "typ": "JWT"])
        let payload = jsonBase64url([
            "iss": credentials.teamID,
            "iat": now,
            "exp": exp,
            "aud": "https://appleid.apple.com",
            "sub": credentials.clientID,
        ] as [String: Any])

        let signingInput = "\(header).\(payload)"
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: credentials.keyContent)
        let sig = try privateKey.signature(for: Data(signingInput.utf8))
        let clientSecret = "\(signingInput).\(base64url(sig.rawRepresentation))"

        var components = URLComponents(string: "https://appleid.apple.com/auth/oauth2/token")!
        components.queryItems = [
            .init(name: "grant_type", value: "client_credentials"),
            .init(name: "client_id", value: credentials.clientID),
            .init(name: "client_secret", value: clientSecret),
            .init(name: "scope", value: "searchadsorg"),
        ]

        var req = URLRequest(url: URL(string: "https://appleid.apple.com/auth/oauth2/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = components.query?.data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return token
    }

    // MARK: - HTTP

    private func authHeaders() async throws -> [String: String] {
        var h: [String: String] = ["Authorization": "Bearer \(try await accessToken())"]
        if let org = orgID { h["X-AP-Context"] = "orgId=\(org)" }
        return h
    }

    private func get(_ path: String) async throws -> [String: Any] {
        let url = URL(string: baseURL + path)!
        var req = URLRequest(url: url)
        for (k, v) in try await authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        try await send("POST", path: path, body: body)
    }

    private func postArray(_ path: String, body: [[String: Any]]) async throws -> [String: Any] {
        let url = URL(string: baseURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        for (k, v) in try await authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func put(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        try await send("PUT", path: path, body: body)
    }

    private func delete(_ path: String) async throws {
        let url = URL(string: baseURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        for (k, v) in try await authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func send(_ method: String, path: String, body: [String: Any]) async throws -> [String: Any] {
        let url = URL(string: baseURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (k, v) in try await authHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func jsonBase64url(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return "" }
        return base64url(data)
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
