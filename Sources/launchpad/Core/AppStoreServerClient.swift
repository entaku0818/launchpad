import Foundation
import CryptoKit

struct AppStoreServerClient {
    private let credentials: ASCCredentials
    private let baseURL: String

    init(credentials: ASCCredentials, sandbox: Bool = false) {
        self.credentials = credentials
        self.baseURL = sandbox
            ? "https://api.storekit-sandbox.itunes.apple.com"
            : "https://api.storekit.itunes.apple.com"
    }

    // MARK: - Transaction History

    func getTransactionHistory(transactionID: String, revision: String? = nil) async throws -> [String: Any] {
        var path = "/inApps/v2/history/\(transactionID)?sort=ASCENDING&productType=AUTO_RENEWABLE_SUBSCRIPTION,NON_CONSUMABLE,CONSUMABLE,NON_RENEWING_SUBSCRIPTION"
        if let rev = revision { path += "&revision=\(rev)" }
        return try await get(path)
    }

    func getAllTransactions(originalTransactionID: String) async throws -> [[String: Any]] {
        var transactions: [[String: Any]] = []
        var revision: String? = nil
        var hasMore = true
        while hasMore {
            let page = try await getTransactionHistory(transactionID: originalTransactionID, revision: revision)
            let items = page["signedTransactions"] as? [String] ?? []
            transactions += items.map { decodeJWTPayload($0) }
            hasMore = page["hasMore"] as? Bool ?? false
            revision = page["revision"] as? String
        }
        return transactions
    }

    // MARK: - Subscription Status

    func getSubscriptionStatuses(originalTransactionID: String) async throws -> [String: Any] {
        return try await get("/inApps/v1/subscriptions/\(originalTransactionID)")
    }

    // MARK: - Refund Lookup

    func getRefundHistory(originalTransactionID: String) async throws -> [[String: Any]] {
        let data = try await get("/inApps/v2/refund/lookup/\(originalTransactionID)")
        let items = data["signedTransactions"] as? [String] ?? []
        return items.map { decodeJWTPayload($0) }
    }

    // MARK: - Notification Testing

    func sendTestNotification() async throws -> String {
        let resp = try await post("/inApps/v1/notifications/test", body: [:])
        return resp["testNotificationToken"] as? String ?? ""
    }

    func getTestNotificationStatus(testToken: String) async throws -> [String: Any] {
        return try await get("/inApps/v1/notifications/test/\(testToken)")
    }

    // MARK: - Notification History

    func getNotificationHistory(startDate: String, endDate: String, notificationType: String? = nil) async throws -> [[String: Any]] {
        var body: [String: Any] = [
            "startDate": startDate,
            "endDate": endDate,
        ]
        if let type = notificationType { body["notificationType"] = type }
        let resp = try await post("/inApps/v1/notifications/history", body: body)
        return resp["notificationHistory"] as? [[String: Any]] ?? []
    }

    // MARK: - Extend Subscription

    func extendSubscriptionRenewalDate(originalTransactionID: String, productID: String, extendByDays: Int, reason: Int = 0) async throws -> String {
        let body: [String: Any] = [
            "extendByDays": extendByDays,
            "extendReasonCode": reason,
            "requestIdentifier": UUID().uuidString,
        ]
        let resp = try await put("/inApps/v1/subscriptions/extend/\(originalTransactionID)", body: body)
        return resp["originalTransactionId"] as? String ?? originalTransactionID
    }

    // MARK: - JWT decode (without verification — display only)

    func decodeJWTPayload(_ token: String) -> [String: Any] {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return ["raw": token] }
        var b64 = String(parts[1])
        while b64.count % 4 != 0 { b64 += "=" }
        let b64std = b64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard let data = Data(base64Encoded: b64std),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["raw": token]
        }
        return json
    }

    // MARK: - HTTP

    private func generateJWT() throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header = try jsonBase64url(["alg": "ES256", "kid": credentials.keyID, "typ": "JWT"])
        let payload = try jsonBase64url([
            "iss": credentials.issuerID,
            "iat": now,
            "exp": now + 1200,
            "aud": "appstoreconnect-v1",
            "bid": "",
        ] as [String: Any])
        let signingInput = "\(header).\(payload)"
        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: credentials.keyContent)
        let signature = try privateKey.signature(for: Data(signingInput.utf8))
        return "\(signingInput).\(base64url(signature.rawRepresentation))"
    }

    private func get(_ path: String) async throws -> [String: Any] {
        let url = URL(string: baseURL + path)!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(try generateJWT())", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }

    private func post(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        try await send("POST", path: path, body: body)
    }

    private func put(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        try await send("PUT", path: path, body: body)
    }

    private func send(_ method: String, path: String, body: [String: Any]) async throws -> [String: Any] {
        let url = URL(string: baseURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(try generateJWT())", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !body.isEmpty {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func jsonBase64url(_ dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict)
        return base64url(data)
    }

    private func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
