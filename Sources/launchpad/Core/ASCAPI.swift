import Foundation

struct ASCAPIClient {
    private let credentials: ASCCredentials
    private let baseURL = "https://api.appstoreconnect.apple.com/v1"

    init(credentials: ASCCredentials) {
        self.credentials = credentials
    }

    // MARK: - Apps

    func findApp(bundleID: String) async throws -> String {
        let data = try await get("/apps?filter[bundleId]=\(bundleID)&fields[apps]=bundleId,name")
        guard
            let apps = data["data"] as? [[String: Any]],
            let id = apps.first?["id"] as? String
        else {
            throw LaunchpadError.appNotFound(bundleID)
        }
        return id
    }

    // MARK: - App Store Versions

    private static let editableStates = [
        "PREPARE_FOR_SUBMISSION",
        "DEVELOPER_REJECTED",
        "REJECTED",
        "METADATA_REJECTED",
        "WAITING_FOR_REVIEW",
        "IN_REVIEW",
    ].joined(separator: ",")

    func getAppStoreVersion(appID: String, version: String) async throws -> String {
        let encoded = version.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? version
        let data = try await get(
            "/apps/\(appID)/appStoreVersions?filter[platform]=IOS&filter[versionString]=\(encoded)&filter[appStoreState]=\(Self.editableStates)"
        )
        guard
            let versions = data["data"] as? [[String: Any]],
            let id = versions.first?["id"] as? String
        else {
            throw LaunchpadError.versionNotFound(version)
        }
        return id
    }

    func getLatestEditableAppStoreVersion(appID: String) async throws -> (id: String, version: String) {
        let data = try await get(
            "/apps/\(appID)/appStoreVersions?filter[platform]=IOS&filter[appStoreState]=\(Self.editableStates)&limit=1"
        )
        guard
            let versions = data["data"] as? [[String: Any]],
            let first = versions.first,
            let id = first["id"] as? String,
            let attrs = first["attributes"] as? [String: Any],
            let versionString = attrs["versionString"] as? String
        else {
            throw LaunchpadError.versionNotFound("(no editable version)")
        }
        return (id, versionString)
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

    // MARK: - TestFlight Beta

    func getBetaGroups(appID: String) async throws -> [[String: Any]] {
        let data = try await get("/betaGroups?filter[app]=\(appID)&fields[betaGroups]=name,isInternalGroup,publicLinkEnabled,publicLink")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getBetaTesters(groupID: String) async throws -> [[String: Any]] {
        let data = try await get("/betaGroups/\(groupID)/betaTesters?fields[betaTesters]=firstName,lastName,email,inviteType,status")
        return data["data"] as? [[String: Any]] ?? []
    }

    func addBetaTester(email: String, firstName: String?, lastName: String?, groupID: String) async throws {
        // create tester
        var attrs: [String: Any] = ["email": email]
        if let firstName { attrs["firstName"] = firstName }
        if let lastName  { attrs["lastName"]  = lastName  }
        let createBody: [String: Any] = [
            "data": [
                "type": "betaTesters",
                "attributes": attrs,
                "relationships": [
                    "betaGroups": ["data": [["type": "betaGroups", "id": groupID]]]
                ],
            ]
        ]
        _ = try await post("/betaTesters", body: createBody)
    }

    func removeBetaTester(email: String, groupID: String) async throws {
        // find tester ID by email
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        let data = try await get("/betaTesters?filter[email]=\(encoded)&filter[betaGroups]=\(groupID)&fields[betaTesters]=email")
        guard
            let testers = data["data"] as? [[String: Any]],
            let testerID = testers.first?["id"] as? String
        else { throw LaunchpadError.appNotFound("tester: \(email)") }

        let body: [String: Any] = ["data": [["type": "betaTesters", "id": testerID]]]
        _ = try await delete("/betaGroups/\(groupID)/relationships/betaTesters", body: body)
    }

    // MARK: - App Preview Videos

    func getPreviewSets(localizationID: String) async throws -> [[String: Any]] {
        let data = try await get("/appStoreVersionLocalizations/\(localizationID)/appPreviewSets")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getPreviews(setID: String) async throws -> [[String: Any]] {
        let data = try await get("/appPreviewSets/\(setID)/appPreviews")
        return data["data"] as? [[String: Any]] ?? []
    }

    func deletePreview(id: String) async throws {
        try await delete("/appPreviews/\(id)")
    }

    func reservePreview(setID: String, fileName: String, fileSize: Int) async throws -> (id: String, uploadURL: String) {
        let body: [String: Any] = [
            "data": [
                "type": "appPreviews",
                "attributes": ["fileName": fileName, "fileSize": fileSize],
                "relationships": [
                    "appPreviewSet": ["data": ["type": "appPreviewSets", "id": setID]]
                ],
            ]
        ]
        let response = try await post("/appPreviews", body: body)
        guard
            let d = response["data"] as? [String: Any],
            let id = d["id"] as? String,
            let attrs = d["attributes"] as? [String: Any],
            let ops = attrs["uploadOperations"] as? [[String: Any]],
            let url = ops.first?["url"] as? String
        else { throw LaunchpadError.invalidResponse }
        return (id, url)
    }

    func commitPreview(id: String, md5: String, fileSize: Int) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "appPreviews",
                "id": id,
                "attributes": ["uploaded": true, "sourceFileChecksum": md5],
            ]
        ]
        _ = try await patch("/appPreviews/\(id)", body: body)
    }

    // MARK: - Pricing & Territory

    func getPriceSchedule(appID: String) async throws -> [String: Any] {
        let data = try await get("/apps/\(appID)/appPriceSchedule?include=manualPrices,baseTerritories")
        return data["data"] as? [String: Any] ?? [:]
    }

    func getAvailableTerritories(appID: String) async throws -> [[String: Any]] {
        let data = try await get("/apps/\(appID)/availableTerritories")
        return data["data"] as? [[String: Any]] ?? []
    }

    // MARK: - Custom Product Pages

    func getCustomProductPages(appID: String) async throws -> [[String: Any]] {
        let data = try await get("/apps/\(appID)/appCustomProductPages?fields[appCustomProductPages]=name,url,visible")
        return data["data"] as? [[String: Any]] ?? []
    }

    // MARK: - Provisioning — Devices

    func listDevices(limit: Int = 50) async throws -> [[String: Any]] {
        let data = try await get("/devices?limit=\(limit)&fields[devices]=name,udid,deviceClass,status,platform")
        return data["data"] as? [[String: Any]] ?? []
    }

    func registerDevice(name: String, udid: String, platform: String = "IOS") async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "devices",
                "attributes": ["name": name, "udid": udid, "platform": platform],
            ]
        ]
        let response = try await post("/devices", body: body)
        guard
            let d = response["data"] as? [String: Any],
            let id = d["id"] as? String
        else { throw LaunchpadError.invalidResponse }
        return id
    }

    // MARK: - Provisioning — Certificates

    func listCertificates() async throws -> [[String: Any]] {
        let data = try await get("/certificates?fields[certificates]=name,certificateType,expirationDate,displayName")
        return data["data"] as? [[String: Any]] ?? []
    }

    // MARK: - In-App Events

    func getAppEvents(appID: String) async throws -> [[String: Any]] {
        let data = try await get("/appEvents?filter[app]=\(appID)&fields[appEvents]=referenceName,badge,eventState,startDate,endDate")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getAppEvent(eventID: String) async throws -> [String: Any] {
        let data = try await get("/appEvents/\(eventID)?include=localizations")
        return data["data"] as? [String: Any] ?? [:]
    }

    func publishAppEvent(eventID: String) async throws {
        _ = try await post("/appEvents/\(eventID)/publish", body: [:])
    }

    func unpublishAppEvent(eventID: String) async throws {
        _ = try await post("/appEvents/\(eventID)/unpublish", body: [:])
    }

    // MARK: - Phased Release

    func getPhasedRelease(versionID: String) async throws -> (id: String, state: String)? {
        let data = try await get("/appStoreVersions/\(versionID)/appStoreVersionPhasedRelease")
        guard
            let d = data["data"] as? [String: Any],
            let id = d["id"] as? String,
            let attrs = d["attributes"] as? [String: Any],
            let state = attrs["phasedReleaseState"] as? String
        else { return nil }
        return (id, state)
    }

    func createPhasedRelease(versionID: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "appStoreVersionPhasedReleases",
                "attributes": ["phasedReleaseState": "INACTIVE"],
                "relationships": [
                    "appStoreVersion": ["data": ["type": "appStoreVersions", "id": versionID]]
                ],
            ]
        ]
        let response = try await post("/appStoreVersionPhasedReleases", body: body)
        guard
            let d = response["data"] as? [String: Any],
            let id = d["id"] as? String
        else { throw LaunchpadError.invalidResponse }
        return id
    }

    func updatePhasedRelease(id: String, state: String) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "appStoreVersionPhasedReleases",
                "id": id,
                "attributes": ["phasedReleaseState": state],
            ]
        ]
        _ = try await patch("/appStoreVersionPhasedReleases/\(id)", body: body)
    }

    func deletePhasedRelease(id: String) async throws {
        try await delete("/appStoreVersionPhasedReleases/\(id)")
    }

    // MARK: - Schedule Release

    func scheduleRelease(versionID: String, date: String?) async throws {
        var attributes: [String: Any]
        if let date {
            attributes = ["releaseType": "SCHEDULED", "earliestReleaseDate": date]
        } else {
            attributes = ["releaseType": "AFTER_APPROVAL"]
        }
        let body: [String: Any] = [
            "data": [
                "type": "appStoreVersions",
                "id": versionID,
                "attributes": attributes,
            ]
        ]
        _ = try await patch("/appStoreVersions/\(versionID)", body: body)
    }

    // MARK: - Customer Reviews

    func getCustomerReviews(appID: String, limit: Int = 20) async throws -> [[String: Any]] {
        let data = try await get("/apps/\(appID)/customerReviews?sort=-createdDate&limit=\(limit)&include=response")
        return data["data"] as? [[String: Any]] ?? []
    }

    func replyToReview(reviewID: String, body: String) async throws {
        let requestBody: [String: Any] = [
            "data": [
                "type": "customerReviewResponses",
                "attributes": ["responseBody": body],
                "relationships": [
                    "review": ["data": ["type": "customerReviews", "id": reviewID]]
                ],
            ]
        ]
        _ = try await post("/customerReviewResponses", body: requestBody)
    }

    func deleteReviewResponse(responseID: String) async throws {
        try await delete("/customerReviewResponses/\(responseID)")
    }

    // MARK: - Analytics Reports

    func requestAnalyticsReport(appID: String, reportType: String, frequency: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "analyticsReportRequests",
                "attributes": ["accessType": "ONGOING"],
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ],
            ]
        ]
        let response = try await post("/analyticsReportRequests", body: body)
        guard
            let d = response["data"] as? [String: Any],
            let id = d["id"] as? String
        else { throw LaunchpadError.invalidResponse }
        return id
    }

    func getAnalyticsReports(requestID: String) async throws -> [[String: Any]] {
        let data = try await get("/analyticsReportRequests/\(requestID)/reports")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getAnalyticsReportInstances(reportID: String) async throws -> [[String: Any]] {
        let data = try await get("/analyticsReports/\(reportID)/instances")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getAnalyticsReportSegments(instanceID: String) async throws -> [[String: Any]] {
        let data = try await get("/analyticsReportInstances/\(instanceID)/segments")
        return data["data"] as? [[String: Any]] ?? []
    }

    // MARK: - Finance Reports

    func downloadFinanceReport(vendorNumber: String, reportDate: String, regionCode: String = "ZZ") async throws -> String {
        let path = "/financeReports?filter[regionCode]=\(regionCode)&filter[reportDate]=\(reportDate)&filter[reportType]=FINANCIAL_REPORT&filter[vendorNumber]=\(vendorNumber)"
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try credentials.generateJWT())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response, data)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Webhooks

    func listWebhooks() async throws -> [[String: Any]] {
        let data = try await get("/webhooks")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createWebhook(name: String, url: String, secret: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "webhooks",
                "attributes": ["name": name, "endpoint": url, "secret": secret, "isEnabled": true],
            ]
        ]
        let response = try await post("/webhooks", body: body)
        guard
            let d = response["data"] as? [String: Any],
            let id = d["id"] as? String
        else { throw LaunchpadError.invalidResponse }
        return id
    }

    func deleteWebhook(id: String) async throws {
        try await delete("/webhooks/\(id)")
    }

    // MARK: - Review Submissions

    func getReviewSubmissions(appID: String) async throws -> [[String: Any]] {
        let data = try await get("/apps/\(appID)/reviewSubmissions?filter[platform]=IOS&limit=10")
        return data["data"] as? [[String: Any]] ?? []
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

    private func delete(_ path: String, body: [String: Any]? = nil) async throws {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(try credentials.generateJWT())", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
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
