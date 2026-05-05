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

    func deactivateBasePlan(packageName: String, productID: String, basePlanID: String) async throws {
        let token = try await accessToken()
        let url = URL(string: "\(baseURL)/applications/\(packageName)/subscriptions/\(productID)/basePlans/\(basePlanID):deactivate")!
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
