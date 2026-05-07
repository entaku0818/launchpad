import Foundation
import CryptoKit

struct NotarizationClient {
    private let credentials: ASCCredentials
    private let baseURL = "https://appstoreconnect.apple.com/notary/v2"

    init(credentials: ASCCredentials) {
        self.credentials = credentials
    }

    // MARK: - Submissions

    func listSubmissions(limit: Int = 10) async throws -> [[String: Any]] {
        let json = try await get("/submissions?limit=\(limit)")
        return json["data"] as? [[String: Any]] ?? []
    }

    func getSubmission(submissionID: String) async throws -> [String: Any] {
        let json = try await get("/submissions/\(submissionID)")
        return json["data"] as? [String: Any] ?? [:]
    }

    func getSubmissionLogs(submissionID: String) async throws -> String {
        let json = try await get("/submissions/\(submissionID)/logs")
        guard let attrs = (json["data"] as? [String: Any])?["attributes"] as? [String: Any],
              let logsURL = attrs["developerLogURL"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        let url = URL(string: logsURL)!
        let (data, _) = try await URLSession.shared.data(from: url)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func submitForNotarization(filePath: String, submissionName: String) async throws -> (id: String, s3Attrs: [String: Any]) {
        let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let sha256 = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()

        let body: [String: Any] = ["sha256": sha256, "submissionName": submissionName]
        let json = try await post("/submissions", body: body)

        guard
            let data = json["data"] as? [String: Any],
            let id = data["id"] as? String,
            let attrs = data["attributes"] as? [String: Any]
        else { throw LaunchpadError.invalidResponse }

        return (id, attrs)
    }

    func uploadToS3(filePath: String, s3Attrs: [String: Any]) async throws {
        guard
            let bucket     = s3Attrs["bucket"] as? String,
            let object     = s3Attrs["object"] as? String,
            let accessKey  = s3Attrs["awsAccessKeyId"] as? String,
            let secretKey  = s3Attrs["awsSecretAccessKey"] as? String,
            let sessionTok = s3Attrs["awsSessionToken"] as? String
        else { throw LaunchpadError.invalidResponse }

        let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent

        let region = "us-east-1"
        let s3URL = URL(string: "https://\(bucket).s3.amazonaws.com/\(object)")!

        let now = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let amzDate = dateFormatter.string(from: now).replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
        let dateStamp = String(amzDate.prefix(8))

        var req = URLRequest(url: s3URL)
        req.httpMethod = "PUT"
        req.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        req.setValue(sessionTok, forHTTPHeaderField: "x-amz-security-token")
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.setValue(fileName, forHTTPHeaderField: "x-apple-notary-submission-name")
        req.httpBody = fileData

        let sha256Body = SHA256.hash(data: fileData).compactMap { String(format: "%02x", $0) }.joined()
        req.setValue(sha256Body, forHTTPHeaderField: "x-amz-content-sha256")

        let signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date;x-amz-security-token;x-apple-notary-submission-name"
        let canonicalHeaders = "content-type:application/octet-stream\nhost:\(bucket).s3.amazonaws.com\nx-amz-content-sha256:\(sha256Body)\nx-amz-date:\(amzDate)\nx-amz-security-token:\(sessionTok)\nx-apple-notary-submission-name:\(fileName)\n"
        let canonicalRequest = "PUT\n/\(object)\n\n\(canonicalHeaders)\n\(signedHeaders)\n\(sha256Body)"

        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(credentialScope)\n" + SHA256.hash(data: Data(canonicalRequest.utf8)).compactMap { String(format: "%02x", $0) }.joined()

        func hmac(_ key: Data, _ msg: String) -> Data {
            let sym = SymmetricKey(data: key)
            return Data(HMAC<SHA256>.authenticationCode(for: Data(msg.utf8), using: sym))
        }

        let kDate    = hmac(Data(("AWS4" + secretKey).utf8), dateStamp)
        let kRegion  = hmac(kDate, region)
        let kService = hmac(kRegion, "s3")
        let kSigning = hmac(kService, "aws4_request")
        let signature = hmac(kSigning, stringToSign).map { String(format: "%02x", $0) }.joined()

        let auth = "AWS4-HMAC-SHA256 Credential=\(accessKey)/\(credentialScope),SignedHeaders=\(signedHeaders),Signature=\(signature)"
        req.setValue(auth, forHTTPHeaderField: "Authorization")

        let (_, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 300 {
            throw LaunchpadError.apiError(http.statusCode, "S3 upload failed")
        }
    }

    // MARK: - HTTP

    private func get(_ path: String) async throws -> [String: Any] {
        let url = URL(string: baseURL + path)!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(try credentials.generateJWT())", forHTTPHeaderField: "Authorization")
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
        let url = URL(string: baseURL + path)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(try credentials.generateJWT())", forHTTPHeaderField: "Authorization")
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
