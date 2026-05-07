import Foundation

struct iTunesSearchClient {
    private let baseURL = "https://itunes.apple.com"

    func searchApps(term: String, country: String = "us", limit: Int = 200) async throws -> [[String: Any]] {
        var components = URLComponents(string: "\(baseURL)/search")!
        components.queryItems = [
            .init(name: "term", value: term),
            .init(name: "country", value: country),
            .init(name: "entity", value: "software"),
            .init(name: "limit", value: "\(limit)"),
        ]
        let (data, resp) = try await URLSession.shared.data(from: components.url!)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw LaunchpadError.apiError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        return results
    }

    func keywordRank(bundleID: String, keywords: [String], country: String = "us") async throws -> [(keyword: String, rank: Int?)] {
        var results: [(keyword: String, rank: Int?)] = []
        for keyword in keywords {
            let apps = try await searchApps(term: keyword, country: country)
            let rank = apps.firstIndex(where: { ($0["bundleId"] as? String) == bundleID }).map { $0 + 1 }
            results.append((keyword: keyword, rank: rank))
            // avoid hitting rate limits
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        return results
    }
}
