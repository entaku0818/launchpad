import CryptoKit
import Foundation

struct GooglePlayClient {
    private let serviceAccountJSON: [String: Any]
    private let baseURL = "https://androidpublisher.googleapis.com/androidpublisher/v3"

    static func fromEnvironment() throws -> GooglePlayClient {
        guard let json = ProcessInfo.processInfo.environment["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON"] else {
            throw LaunchpadError.missingEnvironmentVariable("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
        }
        guard
            let data = json.data(using: .utf8),
            let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw LaunchpadError.invalidResponse
        }
        return GooglePlayClient(serviceAccountJSON: dict)
    }

    init(serviceAccountJSON: [String: Any]) {
        self.serviceAccountJSON = serviceAccountJSON
    }

    // MARK: - Public API

    func uploadAAB(packageName: String, aabPath: String, track: String) async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        let versionCode = try await uploadBundle(
            packageName: packageName,
            aabPath: aabPath,
            editID: editID,
            token: token
        )

        try await updateTrack(
            packageName: packageName,
            editID: editID,
            track: track,
            versionCode: versionCode,
            token: token
        )

        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    func uploadMetadata(packageName: String, track: String, metadataPath: String = "fastlane/metadata/android") async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        let fm = FileManager.default
        let localeDirs = (try? fm.contentsOfDirectory(atPath: metadataPath)) ?? []

        for locale in localeDirs {
            let localeDir = "\(metadataPath)/\(locale)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: localeDir, isDirectory: &isDir), isDir.boolValue else { continue }

            let gpLocale = locale.replacingOccurrences(of: "-", with: "_")
            var listing: [String: String] = [:]

            let fields: [(file: String, key: String)] = [
                ("title.txt",            "title"),
                ("short_description.txt","shortDescription"),
                ("full_description.txt", "fullDescription"),
                ("changelogs/default.txt","recentChanges"),
            ]
            for (file, key) in fields {
                let path = "\(localeDir)/\(file)"
                if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                    listing[key] = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }

            guard !listing.isEmpty else { continue }

            let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/listings/\(gpLocale)")!
            var req = URLRequest(url: url)
            req.httpMethod = "PATCH"
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: listing)
            _ = try await URLSession.shared.data(for: req)
            Logger.success("Updated metadata for \(locale)")
        }

        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    func setRollout(packageName: String, track: String, percentage: Double) async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        let srcURL = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/tracks/\(track)")!
        var srcReq = URLRequest(url: srcURL)
        srcReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (srcData, _) = try await URLSession.shared.data(for: srcReq)
        guard
            let srcJSON = try JSONSerialization.jsonObject(with: srcData) as? [String: Any],
            let releases = srcJSON["releases"] as? [[String: Any]],
            let existingRelease = releases.first,
            let versionCodes = existingRelease["versionCodes"] as? [Int]
        else { throw LaunchpadError.invalidResponse }

        let fraction = min(max(percentage / 100.0, 0.0), 1.0)
        var release: [String: Any] = [
            "status": fraction >= 1.0 ? "completed" : "inProgress",
            "versionCodes": versionCodes,
        ]
        if fraction < 1.0 { release["userFraction"] = fraction }
        let body: [String: Any] = ["track": track, "releases": [release]]
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/tracks/\(track)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await URLSession.shared.data(for: req)

        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    func listReviews(packageName: String, limit: Int = 20) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/reviews?maxResults=\(limit)&translationLanguage=ja")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["reviews"] as? [[String: Any]] ?? []
    }

    func getReview(packageName: String, reviewID: String) async throws -> [String: Any] {
        let token = try await accessToken()
        let encoded = reviewID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? reviewID
        let url = URL(string: "\(baseURL)/applications/\(packageName)/reviews/\(encoded)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    func replyToReview(packageName: String, reviewID: String, text: String) async throws {
        let token = try await accessToken()
        let encoded = reviewID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? reviewID
        let url = URL(string: "\(baseURL)/applications/\(packageName)/reviews/\(encoded):reply")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["replyText": text])
        _ = try await URLSession.shared.data(for: req)
    }

    func shareInternally(packageName: String, aabPath: String) async throws -> String {
        let token = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/\(packageName)/internalappsharingartifacts?uploadType=media")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Data(contentsOf: URL(fileURLWithPath: aabPath))
        let (data, _) = try await URLSession.shared.data(for: req)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let downloadURL = json["downloadUrl"] as? String
        else { throw LaunchpadError.invalidResponse }
        return downloadURL
    }

    func createRecovery(packageName: String, versionCode: Int) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/appRecoveries")!
        let body: [String: Any] = [
            "targeting": ["allUsers": [:]],
            "remediations": [["type": "CANCEL_APP_UPGRADE", "versionCodeTargeting": ["versionCodes": [versionCode]]]],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LaunchpadError.apiError(http.statusCode, body)
        }
    }

    // MARK: - Subscriptions

    func listSubscriptions(packageName: String) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["subscriptions"] as? [[String: Any]] ?? []
    }

    func getSubscription(packageName: String, productID: String) async throws -> [String: Any] {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    func createSubscription(packageName: String, productID: String, referenceName: String, listings: [String: [String: String]]) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "productId": productID,
            "packageName": packageName,
            "listings": listings.mapValues { l -> [String: Any] in
                ["title": l["title"] ?? "", "benefits": l["benefits"] ?? ""]
            }
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func updateSubscription(packageName: String, productID: String, listings: [String: [String: String]]) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)?updateMask=listings")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "listings": listings.mapValues { l -> [String: Any] in
                ["title": l["title"] ?? "", "benefits": l["benefits"] ?? ""]
            }
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func deleteSubscription(packageName: String, productID: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func deactivateSubscription(packageName: String, productID: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID):deactivate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func archiveSubscription(packageName: String, productID: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID):archive")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func deactivateBasePlan(packageName: String, productID: String, basePlanID: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)/basePlans/\(basePlanID):deactivate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func createBasePlan(packageName: String, productID: String, basePlanID: String, billingPeriod: String, regionCodes: [String]) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)/basePlans")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let regionalConfigs: [[String: Any]] = regionCodes.map { code in
            ["regionCode": code, "newSubscriberAvailability": true, "price": [:] as [String: Any]]
        }
        let body: [String: Any] = [
            "basePlanId": basePlanID,
            "autoRenewingBasePlanType": [
                "billingPeriodDuration": billingPeriod,
                "resubscribeState": "RESUBSCRIBE_STATE_ACTIVE",
                "prorationMode": "IMMEDIATE_WITH_TIME_PRORATION",
            ],
            "regionalConfigs": regionalConfigs,
            "state": "DRAFT",
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func deleteBasePlan(packageName: String, productID: String, basePlanID: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)/basePlans/\(basePlanID)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func listBasePlans(packageName: String, productID: String) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)/basePlans")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["basePlans"] as? [[String: Any]] ?? []
    }

    func activateBasePlan(packageName: String, productID: String, basePlanID: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)/basePlans/\(basePlanID):activate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - In-App Products (one-time)

    func listIAP(packageName: String) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/inappproducts")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["inappproduct"] as? [[String: Any]] ?? []
    }

    func getIAP(packageName: String, sku: String) async throws -> [String: Any] {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/inappproducts/\(sku)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    func createIAP(packageName: String, sku: String, productType: String, defaultPrice: Double, defaultPriceCurrency: String, titles: [String: String], descriptions: [String: String]) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/inappproducts")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var listings: [String: [String: String]] = [:]
        for (lang, title) in titles {
            listings[lang] = ["title": title, "description": descriptions[lang] ?? ""]
        }

        let body: [String: Any] = [
            "packageName": packageName,
            "sku": sku,
            "productType": productType,
            "status": "active",
            "defaultPrice": ["priceMicros": "\(Int(defaultPrice * 1_000_000))", "currency": defaultPriceCurrency],
            "listings": listings,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func deleteIAP(packageName: String, sku: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/inappproducts/\(sku)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func updateIAPStatus(packageName: String, sku: String, status: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/inappproducts/\(sku)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["status": status])
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func updateIAPPrice(packageName: String, sku: String, priceMicros: String, priceCurrencyCode: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/inappproducts/\(sku)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "defaultPrice": ["priceMicros": priceMicros, "currency": priceCurrencyCode]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Store Images

    func listImages(packageName: String, language: String, imageType: String) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/listings/\(language)/images/\(imageType)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        _ = try? await URLSession.shared.data(for: {
            var r = URLRequest(url: URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID):delete")!)
            r.httpMethod = "DELETE"; r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); return r
        }())
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["images"] as? [[String: Any]] ?? []
    }

    func uploadImage(packageName: String, language: String, imageType: String, imagePath: String) async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)
        let url = URL(string: "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/\(packageName)/edits/\(editID)/listings/\(language)/images/\(imageType)?uploadType=media")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("image/png", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Data(contentsOf: URL(fileURLWithPath: imagePath))
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    func deleteImage(packageName: String, language: String, imageType: String, imageID: String) async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/listings/\(language)/images/\(imageType)/\(imageID)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            try await abandonEdit(packageName: packageName, editID: editID, token: token)
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    func deleteAllImages(packageName: String, language: String, imageType: String) async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/listings/\(language)/images/\(imageType)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            try await abandonEdit(packageName: packageName, editID: editID, token: token)
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    // MARK: - Subscription Offers

    func getSubscriptionOffer(packageName: String, productID: String, basePlanID: String, offerID: String) async throws -> [String: Any] {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)/basePlans/\(basePlanID)/offers/\(offerID)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    func listSubscriptionOffers(packageName: String, productID: String, basePlanID: String) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)/basePlans/\(basePlanID)/offers")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["offers"] as? [[String: Any]] ?? []
    }

    func createSubscriptionOffer(packageName: String, productID: String, basePlanID: String, offerID: String, phases: [[String: Any]]) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)/basePlans/\(basePlanID)/offers")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "packageName": packageName,
            "productId": productID,
            "basePlanId": basePlanID,
            "offerId": offerID,
            "phases": phases,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func activateOffer(packageName: String, productID: String, basePlanID: String, offerID: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)/basePlans/\(basePlanID)/offers/\(offerID):activate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func deactivateOffer(packageName: String, productID: String, basePlanID: String, offerID: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)/basePlans/\(basePlanID)/offers/\(offerID):deactivate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func deleteOffer(packageName: String, productID: String, basePlanID: String, offerID: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)/basePlans/\(basePlanID)/offers/\(offerID)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Voided Purchases (Refunds)

    func listVoidedPurchases(packageName: String, limit: Int = 20) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/purchases/voidedpurchases?maxResults=\(limit)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["voidedPurchases"] as? [[String: Any]] ?? []
    }

    // MARK: - Expansion Files (OBB)

    func getExpansionFile(packageName: String, versionCode: Int, fileType: String) async throws -> [String: Any] {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/apks/\(versionCode)/expansionFiles/\(fileType)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        _ = try? await URLSession.shared.data(for: {
            var r = URLRequest(url: URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID):delete")!)
            r.httpMethod = "DELETE"; r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); return r
        }())
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    func uploadExpansionFile(packageName: String, versionCode: Int, fileType: String, filePath: String) async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)
        let url = URL(string: "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/\(packageName)/edits/\(editID)/apks/\(versionCode)/expansionFiles/\(fileType)?uploadType=media")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    // MARK: - Managed Publishing

    func getManagedPublishing(packageName: String) async throws -> [String: Any] {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/managedPublishing")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    func setManagedPublishing(packageName: String, enabled: Bool) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/managedPublishing")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["isAutoPublishEnabled": !enabled])
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func publishEdit(packageName: String) async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)
        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    // MARK: - Bundles (uploaded builds)

    func listBundles(packageName: String) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/bundles")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        _ = try? await URLSession.shared.data(for: {
            var r = URLRequest(url: URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID):delete")!)
            r.httpMethod = "DELETE"; r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); return r
        }())
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["bundles"] as? [[String: Any]] ?? []
    }

    // MARK: - Internal App Sharing

    func uploadInternalAppSharingAAB(packageName: String, aabPath: String) async throws -> String {
        let token = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/internalappsharing/\(packageName)/artifacts/bundle?uploadType=media")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Data(contentsOf: URL(fileURLWithPath: aabPath))
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let downloadURL = json["downloadUrl"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return downloadURL
    }

    func uploadInternalAppSharingAPK(packageName: String, apkPath: String) async throws -> String {
        let token = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/internalappsharing/\(packageName)/artifacts/apk?uploadType=media")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Data(contentsOf: URL(fileURLWithPath: apkPath))
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let downloadURL = json["downloadUrl"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return downloadURL
    }

    // MARK: - System APKs

    func listSystemApks(packageName: String, versionCode: Int) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/systemApks/\(versionCode)/variants")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["variants"] as? [[String: Any]] ?? []
    }

    func createSystemApkVariant(packageName: String, versionCode: Int, deviceSpec: [String: Any]) async throws -> Int {
        let token = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/systemApks/\(versionCode)/variants")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["deviceSpec": deviceSpec])
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let variantID = json["variantId"] as? Int else {
            throw LaunchpadError.invalidResponse
        }
        return variantID
    }

    // MARK: - Generated APKs

    func listGeneratedApks(packageName: String, versionCode: Int) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/generatedApks/\(versionCode)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["generatedApks"] as? [[String: Any]] ?? []
    }

    func downloadGeneratedApk(packageName: String, versionCode: Int, downloadID: String, destination: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/generatedApks/\(versionCode)/downloads/\(downloadID):download?alt=media")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        try data.write(to: URL(fileURLWithPath: destination))
    }

    // MARK: - Tracks

    func listTracks(packageName: String) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/tracks")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        _ = try? await URLSession.shared.data(for: {
            var r = URLRequest(url: URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID):delete")!)
            r.httpMethod = "DELETE"; r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); return r
        }())
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["tracks"] as? [[String: Any]] ?? []
    }

    // MARK: - APKs

    func listApks(packageName: String) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/apks")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        _ = try? await URLSession.shared.data(for: {
            var r = URLRequest(url: URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID):delete")!)
            r.httpMethod = "DELETE"; r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); return r
        }())
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["apks"] as? [[String: Any]] ?? []
    }

    // MARK: - Data Safety

    func getDataSafety(packageName: String) async throws -> [String: Any] {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/dataSafety")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    // MARK: - Testers (alpha/beta tracks)

    func getTesters(packageName: String, track: String) async throws -> [String] {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/testers/\(track)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        // discard edit - read-only
        _ = try? await URLSession.shared.data(for: {
            var r = URLRequest(url: URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID):delete")!)
            r.httpMethod = "DELETE"; r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); return r
        }())
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["testers"] as? [String] ?? []
    }

    func setTesters(packageName: String, track: String, emails: [String]) async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/testers/\(track)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["testers": emails])
        _ = try await URLSession.shared.data(for: req)
        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    // MARK: - Country Availability

    func getCountryAvailability(packageName: String, track: String) async throws -> (countries: [String], restOfWorld: Bool) {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/countryavailability/\(track)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        _ = try? await URLSession.shared.data(for: {
            var r = URLRequest(url: URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID):delete")!)
            r.httpMethod = "DELETE"; r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); return r
        }())
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        let countries = (json["countries"] as? [[String: Any]])?.compactMap { $0["countryCode"] as? String } ?? []
        let restOfWorld = json["includeRestOfWorld"] as? Bool ?? false
        return (countries, restOfWorld)
    }

    func setCountryAvailability(packageName: String, track: String, countries: [String], restOfWorld: Bool) async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)
        let body: [String: Any] = [
            "countries": countries.map { ["countryCode": $0] },
            "includeRestOfWorld": restOfWorld,
        ]
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/countryavailability/\(track)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await URLSession.shared.data(for: req)
        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    // MARK: - Users & Grants

    func listUsers() async throws -> [[String: Any]] {
        let token = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/users")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["users"] as? [[String: Any]] ?? []
    }

    func grantUser(email: String, packageName: String, role: String) async throws {
        let token = try await accessToken()
        let developerAccount = (serviceAccountJSON["client_email"] as? String)?
            .components(separatedBy: "@").last?
            .components(separatedBy: ".").first ?? "me"
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/grants")!
        let body: [String: Any] = [
            "name": "developers/\(developerAccount)/users/\(email)/grants",
            "packageName": packageName,
            "appLevelPermissions": [role],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Device Tier Configurations

    func listDeviceTierConfigs(packageName: String) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/deviceTierConfigs")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["deviceTierConfigs"] as? [[String: Any]] ?? []
    }

    // MARK: - Deobfuscation (ProGuard mapping)

    func uploadMapping(packageName: String, versionCode: Int, mappingPath: String, fileType: String = "proguard") async throws {
        let token = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/\(packageName)/deobfuscationfiles/\(versionCode)/\(fileType)?uploadType=media")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Data(contentsOf: URL(fileURLWithPath: mappingPath))
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func listDeobfuscationFiles(packageName: String, versionCode: Int) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/deobfuscationfiles/\(versionCode)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["deobfuscationFiles"] as? [[String: Any]] ?? []
    }

    // MARK: - Track management

    func promoteTrack(packageName: String, from: String, to: String) async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        // Get current releases from source track
        let srcURL = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/tracks/\(from)")!
        var srcReq = URLRequest(url: srcURL)
        srcReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (srcData, _) = try await URLSession.shared.data(for: srcReq)
        guard
            let srcJSON = try JSONSerialization.jsonObject(with: srcData) as? [String: Any],
            let releases = srcJSON["releases"] as? [[String: Any]],
            let versionCodes = releases.first?["versionCodes"] as? [Int]
        else { throw LaunchpadError.invalidResponse }

        try await updateTrack(
            packageName: packageName,
            editID: editID,
            track: to,
            versionCode: versionCodes.last ?? 0,
            token: token
        )
        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    // MARK: - Convert Region Prices

    func convertRegionPrices(packageName: String, priceMicros: Int, currencyCode: String, regionCodes: [String]) async throws -> [String: [String: Any]] {
        let accessTkn = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/pricing:convertRegionPrices")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessTkn)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "price": ["priceMicros": "\(priceMicros)", "currency": currencyCode],
            "regionVersion": ["version": "2022/02"],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let convertedPrices = json["convertedRegionPrices"] as? [String: [String: Any]] else {
            throw LaunchpadError.invalidResponse
        }
        return convertedPrices
    }

    // MARK: - Cancel Surveys

    func listCancelSurveyResults(packageName: String, subscriptionID: String) async throws -> [[String: Any]] {
        let accessTkn = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/purchases/subscriptions/\(subscriptionID)/defer")!
        // Cancel surveys are accessed via the monetization/subscriptions endpoint
        let surveyURL = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/purchases/subscriptionsv2/tokens?subscriptionId=\(subscriptionID)&limit=100")!
        _ = url // suppress unused warning
        var req = URLRequest(url: surveyURL)
        req.setValue("Bearer \(accessTkn)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["subscriptionPurchases"] as? [[String: Any]] ?? []
    }

    func getCancelSurvey(packageName: String, subscriptionID: String, token: String) async throws -> [String: Any] {
        let accessTkn = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/purchases/subscriptionsv2/tokens/\(token)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessTkn)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    // MARK: - Purchase Verification

    func verifyProductPurchase(packageName: String, productID: String, token: String) async throws -> [String: Any] {
        let accessTkn = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/purchases/products/\(productID)/tokens/\(token)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessTkn)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    func verifySubscriptionPurchase(packageName: String, subscriptionID: String, token: String) async throws -> [String: Any] {
        let accessTkn = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/purchases/subscriptions/\(subscriptionID)/tokens/\(token)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessTkn)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    func verifySubscriptionPurchaseV2(packageName: String, token: String) async throws -> [String: Any] {
        let accessTkn = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/purchases/subscriptionsv2/tokens/\(token)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(accessTkn)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    func acknowledgePurchase(packageName: String, productID: String, token: String) async throws {
        let accessTkn = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/purchases/products/\(productID)/tokens/\(token):acknowledge")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessTkn)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (_, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, "acknowledge failed")
        }
    }

    func consumePurchase(packageName: String, productID: String, token: String) async throws {
        let accessTkn = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/purchases/products/\(productID)/tokens/\(token):consume")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessTkn)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    func deferSubscription(packageName: String, subscriptionID: String, token: String, desiredExpiryTimeMillis: Int64) async throws -> Int64 {
        let accessTkn = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/purchases/subscriptions/\(subscriptionID)/tokens/\(token):defer")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessTkn)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "deferralInfo": ["desiredExpiryTimeMillis": String(desiredExpiryTimeMillis)]
        ])
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ms = json["newExpiryTimeMillis"] as? String,
              let millis = Int64(ms) else {
            throw LaunchpadError.invalidResponse
        }
        return millis
    }

    func acknowledgeSubscription(packageName: String, subscriptionID: String, token: String) async throws {
        let accessTkn = try await accessToken()
        let url = URL(string: "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/\(packageName)/purchases/subscriptions/\(subscriptionID)/tokens/\(token):acknowledge")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessTkn)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("{}".utf8)
        let (_, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, "acknowledge failed")
        }
    }

    // MARK: - Bundle Listings (per-bundle release notes)

    func listBundleListings(packageName: String, versionCode: Int) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/bundles/\(versionCode)/listings")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        try await abandonEdit(packageName: packageName, editID: editID, token: token)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["listings"] as? [[String: Any]] ?? []
    }

    // MARK: - APK Listings (per-version release notes)

    func listApkListings(packageName: String, versionCode: Int) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/apks/\(versionCode)/listings")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        try await abandonEdit(packageName: packageName, editID: editID, token: token)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["listings"] as? [[String: Any]] ?? []
    }

    func updateApkListing(packageName: String, versionCode: Int, language: String, recentChanges: String) async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/apks/\(versionCode)/listings/\(language)")!
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["language": language, "recentChanges": recentChanges])
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            try await abandonEdit(packageName: packageName, editID: editID, token: token)
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    // MARK: - App Details

    func getAppDetails(packageName: String) async throws -> [String: Any] {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/details")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        try await abandonEdit(packageName: packageName, editID: editID, token: token)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    func updateAppDetails(packageName: String, defaultLanguage: String?, contactEmail: String?, contactPhone: String?, contactWebsite: String?) async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        var details: [String: Any] = [:]
        if let defaultLanguage { details["defaultLanguage"] = defaultLanguage }
        if let contactEmail    { details["contactEmail"] = contactEmail }
        if let contactPhone    { details["contactPhone"] = contactPhone }
        if let contactWebsite  { details["contactWebsite"] = contactWebsite }

        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/details")!
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: details)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            try await abandonEdit(packageName: packageName, editID: editID, token: token)
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    // MARK: - Orders

    func getOrder(packageName: String, orderID: String) async throws -> [String: Any] {
        let token = try await accessToken()
        let encoded = orderID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? orderID
        let url = URL(string: "\(baseURL)/applications/\(packageName)/orders/\(encoded)")!
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

    func refundOrder(packageName: String, orderID: String, revoke: Bool = false) async throws {
        let token = try await accessToken()
        let encoded = orderID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? orderID
        let url = URL(string: "\(baseURL)/applications/\(packageName)/orders/\(encoded):refund")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["revoke": revoke])
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Store Listings

    func listListings(packageName: String) async throws -> [[String: Any]] {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/listings")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        try await abandonEdit(packageName: packageName, editID: editID, token: token)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json["listings"] as? [[String: Any]] ?? []
    }

    func deleteListing(packageName: String, language: String) async throws {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/listings/\(language)")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            try await abandonEdit(packageName: packageName, editID: editID, token: token)
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        try await commitEdit(packageName: packageName, editID: editID, token: token)
    }

    func getListing(packageName: String, language: String) async throws -> [String: Any] {
        let token = try await accessToken()
        let editID = try await createEdit(packageName: packageName, token: token)

        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/listings/\(language)")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try await abandonEdit(packageName: packageName, editID: editID, token: token)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LaunchpadError.invalidResponse
        }
        return json
    }

    private func abandonEdit(packageName: String, editID: String, token: String) async throws {
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID):delete")!
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - OAuth2

    private func accessToken() async throws -> String {
        guard
            let email = serviceAccountJSON["client_email"] as? String,
            let pemKey = serviceAccountJSON["private_key"] as? String
        else {
            throw LaunchpadError.invalidResponse
        }

        let scope = "https://www.googleapis.com/auth/androidpublisher"
        let now = Int(Date().timeIntervalSince1970)

        let header = base64url(try JSONSerialization.data(withJSONObject: ["alg": "RS256", "typ": "JWT"]))
        let payload = base64url(try JSONSerialization.data(withJSONObject: [
            "iss": email,
            "scope": scope,
            "aud": "https://oauth2.googleapis.com/token",
            "iat": now,
            "exp": now + 3600,
        ] as [String: Any]))

        let signingInput = "\(header).\(payload)"
        let sig = try rsaSign(signingInput, pemKey: pemKey)
        let jwt = "\(signingInput).\(sig)"

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=\(jwt)"
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = json["access_token"] as? String
        else {
            throw LaunchpadError.invalidResponse
        }
        return token
    }

    // MARK: - Edits API

    private func createEdit(packageName: String, token: String) async throws -> String {
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [:])
        let (data, _) = try await URLSession.shared.data(for: req)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = json["id"] as? String
        else { throw LaunchpadError.invalidResponse }
        return id
    }

    private func uploadBundle(packageName: String, aabPath: String, editID: String, token: String) async throws -> Int {
        let url = URL(string: "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/\(packageName)/edits/\(editID)/bundles?uploadType=media")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Data(contentsOf: URL(fileURLWithPath: aabPath))
        let (data, _) = try await URLSession.shared.data(for: req)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let versionCode = json["versionCode"] as? Int
        else { throw LaunchpadError.invalidResponse }
        return versionCode
    }

    private func updateTrack(packageName: String, editID: String, track: String, versionCode: Int, token: String) async throws {
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID)/tracks/\(track)")!
        let body: [String: Any] = [
            "track": track,
            "releases": [["status": "draft", "versionCodes": [versionCode]]],
        ]
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await URLSession.shared.data(for: req)
    }

    private func commitEdit(packageName: String, editID: String, token: String) async throws {
        let url = URL(string: "\(baseURL)/applications/\(packageName)/edits/\(editID):commit")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - RS256 signing using openssl (CryptoKit doesn't support RSA)

    private func rsaSign(_ input: String, pemKey: String) throws -> String {
        let tmpKey = NSTemporaryDirectory() + "gp_\(UUID().uuidString).pem"
        let tmpIn = NSTemporaryDirectory() + "gp_in_\(UUID().uuidString).txt"
        let tmpOut = NSTemporaryDirectory() + "gp_out_\(UUID().uuidString).sig"
        defer {
            try? FileManager.default.removeItem(atPath: tmpKey)
            try? FileManager.default.removeItem(atPath: tmpIn)
            try? FileManager.default.removeItem(atPath: tmpOut)
        }

        try pemKey.write(toFile: tmpKey, atomically: true, encoding: .utf8)
        try input.write(toFile: tmpIn, atomically: true, encoding: .utf8)

        try Shell.run(["openssl", "dgst", "-sha256", "-sign", tmpKey, "-out", tmpOut, tmpIn])
        let sigData = try Data(contentsOf: URL(fileURLWithPath: tmpOut))
        return base64url(sigData)
    }
}

private func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}
