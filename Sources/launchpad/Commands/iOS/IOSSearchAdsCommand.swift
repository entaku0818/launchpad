import ArgumentParser
import Foundation

struct IOSSearchAdsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search-ads",
        abstract: "Apple Search Ads: manage campaigns, ad groups, keywords, and reports",
        subcommands: [
            IOSSearchAdsCampaignsCommand.self,
            IOSSearchAdsAdGroupsCommand.self,
            IOSSearchAdsKeywordsCommand.self,
            IOSSearchAdsNegativeKeywordsCommand.self,
            IOSSearchAdsReportCommand.self,
            IOSSearchAdsBudgetOrdersCommand.self,
        ]
    )
}

// MARK: - helpers

private func makeClient(orgID: String?) throws -> SearchAdsClient {
    return SearchAdsClient(credentials: try SearchAdsCredentials.fromEnvironment(), orgID: orgID)
}

// MARK: - campaigns

struct IOSSearchAdsCampaignsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "campaigns",
        abstract: "List, get, create, update, or delete campaigns",
        subcommands: [
            IOSSearchAdsCampaignsListCommand.self,
            IOSSearchAdsCampaignsGetCommand.self,
            IOSSearchAdsCampaignsCreateCommand.self,
            IOSSearchAdsCampaignsUpdateCommand.self,
            IOSSearchAdsCampaignsDeleteCommand.self,
        ]
    )
}

struct IOSSearchAdsCampaignsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List campaigns")

    @Option(name: .long, help: "Max results (default: 20)")
    var limit: Int = 20

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Fetching campaigns")
        let campaigns = try await client.listCampaigns(limit: limit)
        if campaigns.isEmpty { Logger.info("No campaigns found"); return }
        for c in campaigns {
            let id     = c["id"] as? Int ?? 0
            let name   = c["name"] as? String ?? "-"
            let status = c["status"] as? String ?? "-"
            let budget = (c["budgetAmount"] as? [String: Any]).flatMap { "\($0["amount"] ?? "-") \($0["currency"] ?? "")" } ?? "-"
            print("  [\(id)] \(name)  status: \(status)  budget: \(budget)")
        }
    }
}

struct IOSSearchAdsCampaignsGetCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Get a campaign by ID")

    @Option(name: .long, help: "Campaign ID")
    var campaignID: Int

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Fetching campaign \(campaignID)")
        let c = try await client.getCampaign(campaignID: campaignID)
        let data = try JSONSerialization.data(withJSONObject: c, options: .prettyPrinted)
        print(String(data: data, encoding: .utf8) ?? "{}")
    }
}

struct IOSSearchAdsCampaignsCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create a new campaign")

    @Option(name: .long, help: "Campaign name")
    var name: String

    @Option(name: .long, help: "App Adam ID")
    var appAdamID: Int

    @Option(name: .long, help: "Budget amount (e.g. 100.00)")
    var budget: String

    @Option(name: .long, help: "Currency code (e.g. USD, JPY)")
    var currency: String

    @Option(name: .long, parsing: .upToNextOption, help: "Country/region codes (e.g. JP US)")
    var countries: [String]

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Creating campaign \"\(name)\"")
        let id = try await client.createCampaign(name: name, appAdamID: appAdamID, budgetAmount: budget, currency: currency, countryCodes: countries)
        Logger.success("Campaign created with ID: \(id)")
    }
}

struct IOSSearchAdsCampaignsUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "update", abstract: "Update a campaign")

    @Option(name: .long, help: "Campaign ID")
    var campaignID: Int

    @Option(name: .long, help: "New name")
    var name: String?

    @Option(name: .long, help: "New status (ENABLED or PAUSED)")
    var status: String?

    @Option(name: .long, help: "New budget amount")
    var budget: String?

    @Option(name: .long, help: "Currency code (required if --budget is set)")
    var currency: String?

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Updating campaign \(campaignID)")
        try await client.updateCampaign(campaignID: campaignID, name: name, status: status, budgetAmount: budget, currency: currency)
        Logger.success("Campaign updated")
    }
}

struct IOSSearchAdsCampaignsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a campaign")

    @Option(name: .long, help: "Campaign ID")
    var campaignID: Int

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Deleting campaign \(campaignID)")
        try await client.deleteCampaign(campaignID: campaignID)
        Logger.success("Campaign deleted")
    }
}

// MARK: - ad groups

struct IOSSearchAdsAdGroupsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "adgroups",
        abstract: "List, create, or delete ad groups",
        subcommands: [
            IOSSearchAdsAdGroupsListCommand.self,
            IOSSearchAdsAdGroupsCreateCommand.self,
            IOSSearchAdsAdGroupsDeleteCommand.self,
        ]
    )
}

struct IOSSearchAdsAdGroupsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List ad groups in a campaign")

    @Option(name: .long, help: "Campaign ID")
    var campaignID: Int

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Fetching ad groups for campaign \(campaignID)")
        let groups = try await client.listAdGroups(campaignID: campaignID)
        if groups.isEmpty { Logger.info("No ad groups found"); return }
        for g in groups {
            let id     = g["id"] as? Int ?? 0
            let name   = g["name"] as? String ?? "-"
            let status = g["status"] as? String ?? "-"
            let bid    = (g["cpcBidAmount"] as? [String: Any]).flatMap { "\($0["amount"] ?? "-") \($0["currency"] ?? "")" } ?? "-"
            print("  [\(id)] \(name)  status: \(status)  cpcBid: \(bid)")
        }
    }
}

struct IOSSearchAdsAdGroupsCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create", abstract: "Create an ad group")

    @Option(name: .long, help: "Campaign ID")
    var campaignID: Int

    @Option(name: .long, help: "Ad group name")
    var name: String

    @Option(name: .long, help: "CPC bid amount")
    var bid: String

    @Option(name: .long, help: "Currency code")
    var currency: String

    @Option(name: .long, help: "Start time in ISO8601 (e.g. 2024-01-01T00:00:00.000)")
    var startTime: String

    @Option(name: .long, help: "End time in ISO8601 (optional)")
    var endTime: String?

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Creating ad group \"\(name)\" in campaign \(campaignID)")
        let id = try await client.createAdGroup(campaignID: campaignID, name: name, cpcBidAmount: bid, currency: currency, startTime: startTime, endTime: endTime)
        Logger.success("Ad group created with ID: \(id)")
    }
}

struct IOSSearchAdsAdGroupsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete an ad group")

    @Option(name: .long, help: "Campaign ID")
    var campaignID: Int

    @Option(name: .long, help: "Ad group ID")
    var adGroupID: Int

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Deleting ad group \(adGroupID) from campaign \(campaignID)")
        try await client.deleteAdGroup(campaignID: campaignID, adGroupID: adGroupID)
        Logger.success("Ad group deleted")
    }
}

// MARK: - keywords

struct IOSSearchAdsKeywordsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keywords",
        abstract: "List, add, or delete targeting keywords",
        subcommands: [
            IOSSearchAdsKeywordsListCommand.self,
            IOSSearchAdsKeywordsAddCommand.self,
            IOSSearchAdsKeywordsDeleteCommand.self,
        ]
    )
}

struct IOSSearchAdsKeywordsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List keywords in an ad group")

    @Option(name: .long, help: "Campaign ID")
    var campaignID: Int

    @Option(name: .long, help: "Ad group ID")
    var adGroupID: Int

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Fetching keywords for ad group \(adGroupID)")
        let keywords = try await client.listKeywords(campaignID: campaignID, adGroupID: adGroupID)
        if keywords.isEmpty { Logger.info("No keywords found"); return }
        for kw in keywords {
            let id        = kw["id"] as? Int ?? 0
            let text      = kw["text"] as? String ?? "-"
            let matchType = kw["matchType"] as? String ?? "-"
            let status    = kw["status"] as? String ?? "-"
            let bid       = (kw["bidAmount"] as? [String: Any]).flatMap { "\($0["amount"] ?? "-")" } ?? "-"
            print("  [\(id)] \"\(text)\"  match: \(matchType)  status: \(status)  bid: \(bid)")
        }
    }
}

struct IOSSearchAdsKeywordsAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Add keywords to an ad group (BROAD or EXACT match)")

    @Option(name: .long, help: "Campaign ID")
    var campaignID: Int

    @Option(name: .long, help: "Ad group ID")
    var adGroupID: Int

    @Option(name: .long, parsing: .upToNextOption, help: "Keywords to add")
    var keywords: [String]

    @Option(name: .long, help: "Match type: BROAD or EXACT (default: BROAD)")
    var matchType: String = "BROAD"

    @Option(name: .long, help: "Bid amount (optional)")
    var bid: String?

    @Option(name: .long, help: "Currency code (required if --bid is set)")
    var currency: String?

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Adding \(keywords.count) keyword(s) to ad group \(adGroupID)")
        let kwTuples = keywords.map { (text: $0, matchType: matchType, bidAmount: bid, currency: currency) }
        let added = try await client.addKeywords(campaignID: campaignID, adGroupID: adGroupID, keywords: kwTuples)
        Logger.success("Added \(added.count) keyword(s)")
        for kw in added {
            let id   = kw["id"] as? Int ?? 0
            let text = kw["text"] as? String ?? "-"
            print("  [\(id)] \"\(text)\"")
        }
    }
}

struct IOSSearchAdsKeywordsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete", abstract: "Delete a keyword from an ad group")

    @Option(name: .long, help: "Campaign ID")
    var campaignID: Int

    @Option(name: .long, help: "Ad group ID")
    var adGroupID: Int

    @Option(name: .long, help: "Keyword ID")
    var keywordID: Int

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Deleting keyword \(keywordID)")
        try await client.deleteKeyword(campaignID: campaignID, adGroupID: adGroupID, keywordID: keywordID)
        Logger.success("Keyword deleted")
    }
}

// MARK: - negative keywords

struct IOSSearchAdsNegativeKeywordsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "negative-keywords",
        abstract: "List or add negative keywords for a campaign",
        subcommands: [
            IOSSearchAdsNegativeKeywordsListCommand.self,
            IOSSearchAdsNegativeKeywordsAddCommand.self,
        ]
    )
}

struct IOSSearchAdsNegativeKeywordsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "list", abstract: "List negative keywords for a campaign")

    @Option(name: .long, help: "Campaign ID")
    var campaignID: Int

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Fetching negative keywords for campaign \(campaignID)")
        let keywords = try await client.listNegativeKeywords(campaignID: campaignID)
        if keywords.isEmpty { Logger.info("No negative keywords found"); return }
        for kw in keywords {
            let id        = kw["id"] as? Int ?? 0
            let text      = kw["text"] as? String ?? "-"
            let matchType = kw["matchType"] as? String ?? "-"
            print("  [\(id)] \"\(text)\"  match: \(matchType)")
        }
    }
}

struct IOSSearchAdsNegativeKeywordsAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "add", abstract: "Add negative keywords to a campaign")

    @Option(name: .long, help: "Campaign ID")
    var campaignID: Int

    @Option(name: .long, parsing: .upToNextOption, help: "Keywords to block")
    var keywords: [String]

    @Option(name: .long, help: "Match type: BROAD or EXACT (default: BROAD)")
    var matchType: String = "BROAD"

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Adding \(keywords.count) negative keyword(s) to campaign \(campaignID)")
        let kwTuples = keywords.map { (text: $0, matchType: matchType) }
        let added = try await client.addNegativeKeywords(campaignID: campaignID, keywords: kwTuples)
        Logger.success("Added \(added.count) negative keyword(s)")
    }
}

// MARK: - reports

struct IOSSearchAdsReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Pull campaign, keyword, or ad group performance reports",
        subcommands: [
            IOSSearchAdsReportCampaignsCommand.self,
            IOSSearchAdsReportKeywordsCommand.self,
            IOSSearchAdsReportAdGroupsCommand.self,
        ]
    )
}

struct IOSSearchAdsReportCampaignsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "campaigns", abstract: "Campaign-level performance report")

    @Option(name: .long, help: "Start date (YYYY-MM-DD)")
    var startDate: String

    @Option(name: .long, help: "End date (YYYY-MM-DD)")
    var endDate: String

    @Option(name: .long, help: "Granularity: DAILY, WEEKLY, or MONTHLY (default: DAILY)")
    var granularity: String = "DAILY"

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Fetching campaign report \(startDate) → \(endDate)")
        let result = try await client.reportCampaigns(startDate: startDate, endDate: endDate, granularity: granularity)
        printReport(result)
    }
}

struct IOSSearchAdsReportKeywordsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "keywords", abstract: "Keyword-level performance report")

    @Option(name: .long, help: "Campaign ID")
    var campaignID: Int

    @Option(name: .long, help: "Start date (YYYY-MM-DD)")
    var startDate: String

    @Option(name: .long, help: "End date (YYYY-MM-DD)")
    var endDate: String

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Fetching keyword report for campaign \(campaignID)")
        let result = try await client.reportKeywords(campaignID: campaignID, startDate: startDate, endDate: endDate)
        printReport(result)
    }
}

struct IOSSearchAdsReportAdGroupsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "adgroups", abstract: "Ad group-level performance report")

    @Option(name: .long, help: "Campaign ID")
    var campaignID: Int

    @Option(name: .long, help: "Start date (YYYY-MM-DD)")
    var startDate: String

    @Option(name: .long, help: "End date (YYYY-MM-DD)")
    var endDate: String

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Fetching ad group report for campaign \(campaignID)")
        let result = try await client.reportAdGroups(campaignID: campaignID, startDate: startDate, endDate: endDate)
        printReport(result)
    }
}

private func printReport(_ result: [String: Any]) {
    let rows = (result["data"] as? [String: Any]).flatMap { $0["reportingDataResponse"] as? [String: Any] }.flatMap { $0["row"] as? [[String: Any]] } ?? []
    if rows.isEmpty { Logger.info("No report data"); return }
    for row in rows {
        let metadata  = row["metadata"] as? [String: Any] ?? [:]
        let totals    = row["total"] as? [String: Any] ?? [:]
        let name      = metadata["campaignName"] as? String ?? metadata["adGroupName"] as? String ?? metadata["keyword"] as? String ?? "-"
        let spend     = (totals["localSpend"] as? [String: Any]).flatMap { $0["amount"] as? String } ?? "-"
        let impressions = totals["impressions"] as? Int ?? 0
        let taps        = totals["taps"] as? Int ?? 0
        let installs    = totals["installs"] as? Int ?? 0
        print("  \(name)  spend: \(spend)  imp: \(impressions)  taps: \(taps)  installs: \(installs)")
    }
    if let grand = (result["data"] as? [String: Any]).flatMap({ $0["reportingDataResponse"] as? [String: Any] }).flatMap({ $0["grandTotals"] as? [String: Any] }) {
        let spend = (grand["localSpend"] as? [String: Any]).flatMap { $0["amount"] as? String } ?? "-"
        print("\n  Total spend: \(spend)")
    }
}

// MARK: - budget orders

struct IOSSearchAdsBudgetOrdersCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "budget-orders", abstract: "List budget orders")

    @Option(name: .long, help: "Org ID (overrides SEARCH_ADS_ORG_ID)")
    var orgID: String?

    mutating func run() async throws {
        DotEnv.load()
        let client = try makeClient(orgID: orgID)
        Logger.step("Fetching budget orders")
        let orders = try await client.listBudgetOrders()
        if orders.isEmpty { Logger.info("No budget orders found"); return }
        for o in orders {
            let id     = o["id"] as? Int ?? 0
            let name   = o["name"] as? String ?? "-"
            let status = o["status"] as? String ?? "-"
            let budget = (o["budget"] as? [String: Any]).flatMap { "\($0["amount"] ?? "-") \($0["currency"] ?? "")" } ?? "-"
            print("  [\(id)] \(name)  status: \(status)  budget: \(budget)")
        }
    }
}
