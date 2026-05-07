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

    func createLocalization(versionID: String, locale: String, attributes: [String: Any]) async throws -> String {
        var attrs = attributes
        attrs["locale"] = locale
        let body: [String: Any] = [
            "data": [
                "type": "appStoreVersionLocalizations",
                "attributes": attrs,
                "relationships": [
                    "appStoreVersion": ["data": ["type": "appStoreVersions", "id": versionID]]
                ],
            ]
        ]
        let response = try await post("/appStoreVersionLocalizations", body: body)
        guard let d = response["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteLocalization(localizationID: String) async throws {
        try await delete("/appStoreVersionLocalizations/\(localizationID)")
    }

    // MARK: - Subscription Promotional Offers

    func listPromotionalOffers(subscriptionID: String) async throws -> [[String: Any]] {
        let data = try await get("/subscriptions/\(subscriptionID)/promotionalOffers")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createPromotionalOffer(subscriptionID: String, offerID: String, name: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "subscriptionPromotionalOffers",
                "attributes": [
                    "offerId": offerID,
                    "name": name,
                ],
                "relationships": [
                    "subscription": ["data": ["type": "subscriptions", "id": subscriptionID]]
                ],
            ]
        ]
        let response = try await post("/subscriptionPromotionalOffers", body: body)
        guard let d = response["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deletePromotionalOffer(offerID: String) async throws {
        try await delete("/subscriptionPromotionalOffers/\(offerID)")
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

    func reorderScreenshot(id: String, displayOrder: Int) async throws {
        let body: [String: Any] = [
            "data": ["type": "appScreenshots", "id": id, "attributes": ["displayOrder": displayOrder]]
        ]
        _ = try await patch("/appScreenshots/\(id)", body: body)
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

    // MARK: - Preview Sets

    func getPreviewSets(localizationID: String) async throws -> [[String: Any]] {
        let data = try await get("/appStoreVersionLocalizations/\(localizationID)/appPreviewSets")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getPreviews(setID: String) async throws -> [[String: Any]] {
        let data = try await get("/appPreviewSets/\(setID)/appPreviews")
        return data["data"] as? [[String: Any]] ?? []
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

    func deletePreview(id: String) async throws {
        try await delete("/appPreviews/\(id)")
    }

    func createPreviewSet(localizationID: String, previewType: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "appPreviewSets",
                "attributes": ["previewType": previewType],
                "relationships": [
                    "appStoreVersionLocalization": ["data": ["type": "appStoreVersionLocalizations", "id": localizationID]]
                ],
            ]
        ]
        let response = try await post("/appPreviewSets", body: body)
        guard let d = response["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deletePreviewSet(setID: String) async throws {
        try await delete("/appPreviewSets/\(setID)")
    }

    // MARK: - Subscription Group Localizations

    func listSubscriptionGroupLocalizations(groupID: String) async throws -> [[String: Any]] {
        let data = try await get("/subscriptionGroups/\(groupID)/subscriptionGroupLocalizations")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createSubscriptionGroupLocalization(groupID: String, locale: String, name: String, customAppName: String?) async throws -> String {
        var attrs: [String: Any] = ["locale": locale, "name": name]
        if let customAppName { attrs["customAppName"] = customAppName }
        let body: [String: Any] = [
            "data": [
                "type": "subscriptionGroupLocalizations",
                "attributes": attrs,
                "relationships": [
                    "subscriptionGroup": ["data": ["type": "subscriptionGroups", "id": groupID]]
                ],
            ]
        ]
        let response = try await post("/subscriptionGroupLocalizations", body: body)
        guard let d = response["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func updateSubscriptionGroupLocalization(localizationID: String, name: String?, customAppName: String?) async throws {
        var attrs: [String: Any] = [:]
        if let name { attrs["name"] = name }
        if let customAppName { attrs["customAppName"] = customAppName }
        let body: [String: Any] = [
            "data": [
                "type": "subscriptionGroupLocalizations",
                "id": localizationID,
                "attributes": attrs,
            ]
        ]
        _ = try await patch("/subscriptionGroupLocalizations/\(localizationID)", body: body)
    }

    func deleteSubscriptionGroupLocalization(localizationID: String) async throws {
        try await delete("/subscriptionGroupLocalizations/\(localizationID)")
    }

    // MARK: - Build Beta Details

    func getBuildBetaDetail(buildID: String) async throws -> [String: Any] {
        let data = try await get("/builds/\(buildID)/buildBetaDetail")
        return data["data"] as? [String: Any] ?? [:]
    }

    func updateBuildBetaDetail(detailID: String, whatsNew: String?, autoNotifyEnabled: Bool?) async throws {
        var attrs: [String: Any] = [:]
        if let whatsNew { attrs["whatsNew"] = whatsNew }
        if let autoNotifyEnabled { attrs["autoNotifyEnabled"] = autoNotifyEnabled }
        let body: [String: Any] = [
            "data": [
                "type": "buildBetaDetails",
                "id": detailID,
                "attributes": attrs,
            ]
        ]
        _ = try await patch("/buildBetaDetails/\(detailID)", body: body)
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

    func createBetaGroup(appID: String, name: String, publicLinkEnabled: Bool, feedbackEnabled: Bool) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "betaGroups",
                "attributes": [
                    "name": name,
                    "isInternalGroup": false,
                    "publicLinkEnabled": publicLinkEnabled,
                    "feedbackEnabled": feedbackEnabled,
                ],
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ]
            ]
        ]
        let json = try await post("/betaGroups", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteBetaGroup(groupID: String) async throws {
        try await delete("/betaGroups/\(groupID)")
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

    // MARK: - Pricing & Territory

    func getPriceSchedule(appID: String) async throws -> [String: Any] {
        let data = try await get("/apps/\(appID)/appPriceSchedule?include=manualPrices,baseTerritories")
        return data["data"] as? [String: Any] ?? [:]
    }

    func setAppPriceSchedule(appID: String, pricePointID: String, startDate: String?) async throws {
        var manualPrice: [String: Any] = [
            "type": "appPrices",
            "attributes": ["startDate": startDate as Any],
            "relationships": [
                "appPricePoint": ["data": ["type": "appPricePoints", "id": pricePointID]]
            ]
        ]
        if startDate == nil { manualPrice["attributes"] = [:] as [String: Any] }
        let body: [String: Any] = [
            "data": [
                "type": "appPriceSchedules",
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]],
                    "manualPrices": ["data": [manualPrice]]
                ]
            ]
        ]
        _ = try await post("/appPriceSchedules", body: body)
    }

    func updateBetaGroup(groupID: String, publicLinkEnabled: Bool?, feedbackEnabled: Bool?) async throws {
        var attrs: [String: Any] = [:]
        if let p = publicLinkEnabled { attrs["publicLinkEnabled"] = p }
        if let f = feedbackEnabled { attrs["feedbackEnabled"] = f }
        let body: [String: Any] = [
            "data": [
                "type": "betaGroups",
                "id": groupID,
                "attributes": attrs,
            ]
        ]
        _ = try await patch("/betaGroups/\(groupID)", body: body)
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

    func createCustomProductPage(appID: String, name: String, url: String?) async throws -> String {
        var attrs: [String: Any] = ["name": name]
        if let url { attrs["url"] = url }
        let body: [String: Any] = [
            "data": [
                "type": "appCustomProductPages",
                "attributes": attrs,
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ]
            ]
        ]
        let json = try await post("/appCustomProductPages", body: body)
        guard let d = json["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func updateCustomProductPageVisibility(pageID: String, visible: Bool) async throws {
        let body: [String: Any] = [
            "data": ["type": "appCustomProductPages", "id": pageID, "attributes": ["visible": visible]]
        ]
        _ = try await patch("/appCustomProductPages/\(pageID)", body: body)
    }

    func deleteCustomProductPage(pageID: String) async throws {
        try await delete("/appCustomProductPages/\(pageID)")
    }

    func listCustomProductPageVersions(pageID: String) async throws -> [[String: Any]] {
        let data = try await get("/appCustomProductPages/\(pageID)/appCustomProductPageVersions")
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

    // MARK: - Provisioning — Bundle IDs

    func listBundleIDs(limit: Int = 50) async throws -> [[String: Any]] {
        let json = try await get("/bundleIds?limit=\(limit)&fields[bundleIds]=identifier,name,platform,seedId")
        return json["data"] as? [[String: Any]] ?? []
    }

    func registerBundleID(identifier: String, name: String, platform: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "bundleIds",
                "attributes": [
                    "identifier": identifier,
                    "name": name,
                    "platform": platform,
                ]
            ]
        ]
        let json = try await post("/bundleIds", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteBundleID(bundleIDResourceID: String) async throws {
        try await delete("/bundleIds/\(bundleIDResourceID)")
    }

    func listBundleIDCapabilities(bundleIDResourceID: String) async throws -> [[String: Any]] {
        let data = try await get("/bundleIds/\(bundleIDResourceID)/bundleIdCapabilities")
        return data["data"] as? [[String: Any]] ?? []
    }

    func enableBundleIDCapability(bundleIDResourceID: String, capabilityType: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "bundleIdCapabilities",
                "attributes": ["capabilityType": capabilityType, "settings": []],
                "relationships": [
                    "bundleId": ["data": ["type": "bundleIds", "id": bundleIDResourceID]]
                ]
            ]
        ]
        let json = try await post("/bundleIdCapabilities", body: body)
        guard let d = json["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func disableBundleIDCapability(capabilityID: String) async throws {
        try await delete("/bundleIdCapabilities/\(capabilityID)")
    }

    func createProfile(name: String, profileType: String, bundleIDResourceID: String, certificateIDs: [String], deviceIDs: [String]) async throws -> (id: String, content: Data) {
        let certs = certificateIDs.map { ["type": "certificates", "id": $0] }
        let devs  = deviceIDs.map    { ["type": "devices",      "id": $0] }
        let body: [String: Any] = [
            "data": [
                "type": "profiles",
                "attributes": ["name": name, "profileType": profileType],
                "relationships": [
                    "bundleId":     ["data": ["type": "bundleIds",     "id": bundleIDResourceID]],
                    "certificates": ["data": certs],
                    "devices":      ["data": devs],
                ]
            ]
        ]
        let json = try await post("/profiles", body: body)
        guard
            let d = json["data"] as? [String: Any],
            let id = d["id"] as? String,
            let attrs = d["attributes"] as? [String: Any],
            let content = attrs["profileContent"] as? String,
            let profileData = Data(base64Encoded: content)
        else {
            throw LaunchpadError.invalidResponse
        }
        return (id, profileData)
    }

    // MARK: - Provisioning — Profiles

    func listProfiles(limit: Int = 50) async throws -> [[String: Any]] {
        let json = try await get("/profiles?limit=\(limit)&fields[profiles]=name,profileType,profileState,expirationDate,uuid")
        return json["data"] as? [[String: Any]] ?? []
    }

    func downloadProfile(profileID: String) async throws -> Data {
        let json = try await get("/profiles/\(profileID)?fields[profiles]=profileContent")
        guard
            let data = json["data"] as? [String: Any],
            let attrs = data["attributes"] as? [String: Any],
            let content = attrs["profileContent"] as? String,
            let profileData = Data(base64Encoded: content)
        else {
            throw LaunchpadError.invalidResponse
        }
        return profileData
    }

    func deleteProfile(profileID: String) async throws {
        try await delete("/profiles/\(profileID)")
    }

    // MARK: - Provisioning — Certificates

    func listCertificates() async throws -> [[String: Any]] {
        let data = try await get("/certificates?fields[certificates]=name,certificateType,expirationDate,displayName")
        return data["data"] as? [[String: Any]] ?? []
    }

    func revokeCertificate(certificateID: String) async throws {
        try await delete("/certificates/\(certificateID)")
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

    func createAppEvent(appID: String, referenceName: String, badge: String, startDate: String, endDate: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "appEvents",
                "attributes": [
                    "referenceName": referenceName,
                    "badge": badge,
                    "startDate": startDate,
                    "endDate": endDate,
                ],
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ]
            ]
        ]
        let json = try await post("/appEvents", body: body)
        guard let d = json["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func updateAppEvent(eventID: String, referenceName: String?, badge: String?, startDate: String?, endDate: String?) async throws {
        var attrs: [String: Any] = [:]
        if let referenceName { attrs["referenceName"] = referenceName }
        if let badge { attrs["badge"] = badge }
        if let startDate { attrs["startDate"] = startDate }
        if let endDate { attrs["endDate"] = endDate }
        let body: [String: Any] = [
            "data": ["type": "appEvents", "id": eventID, "attributes": attrs]
        ]
        _ = try await patch("/appEvents/\(eventID)", body: body)
    }

    func deleteAppEvent(eventID: String) async throws {
        try await delete("/appEvents/\(eventID)")
    }

    func publishAppEvent(eventID: String) async throws {
        _ = try await post("/appEvents/\(eventID)/publish", body: [:])
    }

    func unpublishAppEvent(eventID: String) async throws {
        _ = try await post("/appEvents/\(eventID)/unpublish", body: [:])
    }

    // MARK: - App Event Localizations

    func listAppEventLocalizations(eventID: String) async throws -> [[String: Any]] {
        let data = try await get("/appEvents/\(eventID)/localizations")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createAppEventLocalization(eventID: String, locale: String, name: String, shortDescription: String?, longDescription: String?) async throws -> String {
        var attrs: [String: Any] = ["locale": locale, "name": name]
        if let shortDescription { attrs["shortDescription"] = shortDescription }
        if let longDescription { attrs["longDescription"] = longDescription }
        let body: [String: Any] = [
            "data": [
                "type": "appEventLocalizations",
                "attributes": attrs,
                "relationships": [
                    "appEvent": ["data": ["type": "appEvents", "id": eventID]]
                ]
            ]
        ]
        let json = try await post("/appEventLocalizations", body: body)
        guard let d = json["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func updateAppEventLocalization(localizationID: String, name: String?, shortDescription: String?, longDescription: String?) async throws {
        var attrs: [String: Any] = [:]
        if let name { attrs["name"] = name }
        if let shortDescription { attrs["shortDescription"] = shortDescription }
        if let longDescription { attrs["longDescription"] = longDescription }
        let body: [String: Any] = [
            "data": ["type": "appEventLocalizations", "id": localizationID, "attributes": attrs]
        ]
        _ = try await patch("/appEventLocalizations/\(localizationID)", body: body)
    }

    func deleteAppEventLocalization(localizationID: String) async throws {
        try await delete("/appEventLocalizations/\(localizationID)")
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

    // MARK: - Version Release Request (manual hold release)

    func requestVersionRelease(versionID: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "appStoreVersionReleaseRequests",
                "relationships": [
                    "appStoreVersion": ["data": ["type": "appStoreVersions", "id": versionID]]
                ],
            ]
        ]
        let response = try await post("/appStoreVersionReleaseRequests", body: body)
        guard let d = response["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    // MARK: - Subscription Introductory Offers

    func listIntroductoryOffers(subscriptionID: String) async throws -> [[String: Any]] {
        let data = try await get("/subscriptions/\(subscriptionID)/introductoryOffers")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createIntroductoryOffer(subscriptionID: String, duration: String, offerMode: String, numberOfPeriods: Int, territory: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "subscriptionIntroductoryOffers",
                "attributes": [
                    "duration": duration,
                    "offerMode": offerMode,
                    "numberOfPeriods": numberOfPeriods,
                ],
                "relationships": [
                    "subscription": ["data": ["type": "subscriptions", "id": subscriptionID]],
                    "territory": ["data": ["type": "territories", "id": territory]],
                ],
            ]
        ]
        let response = try await post("/subscriptionIntroductoryOffers", body: body)
        guard let d = response["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteIntroductoryOffer(offerID: String) async throws {
        try await delete("/subscriptionIntroductoryOffers/\(offerID)")
    }

    // MARK: - Custom Product Page Localizations

    func listCustomProductPageLocalizations(pageVersionID: String) async throws -> [[String: Any]] {
        let data = try await get("/appCustomProductPageVersions/\(pageVersionID)/appCustomProductPageLocalizations")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createCustomProductPageLocalization(pageVersionID: String, locale: String, promotionalText: String?) async throws -> String {
        var attrs: [String: Any] = ["locale": locale]
        if let text = promotionalText { attrs["promotionalText"] = text }
        let body: [String: Any] = [
            "data": [
                "type": "appCustomProductPageLocalizations",
                "attributes": attrs,
                "relationships": [
                    "appCustomProductPageVersion": ["data": ["type": "appCustomProductPageVersions", "id": pageVersionID]]
                ],
            ]
        ]
        let response = try await post("/appCustomProductPageLocalizations", body: body)
        guard let d = response["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func updateCustomProductPageLocalization(localizationID: String, promotionalText: String) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "appCustomProductPageLocalizations",
                "id": localizationID,
                "attributes": ["promotionalText": promotionalText],
            ]
        ]
        _ = try await patch("/appCustomProductPageLocalizations/\(localizationID)", body: body)
    }

    func deleteCustomProductPageLocalization(localizationID: String) async throws {
        try await delete("/appCustomProductPageLocalizations/\(localizationID)")
    }

    // MARK: - Customer Reviews

    func getCustomerReviews(appID: String, limit: Int = 20) async throws -> [[String: Any]] {
        let data = try await get("/apps/\(appID)/customerReviews?sort=-createdDate&limit=\(limit)&include=response")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getCustomerReview(reviewID: String) async throws -> [String: Any] {
        let data = try await get("/customerReviews/\(reviewID)?include=response")
        return data["data"] as? [String: Any] ?? [:]
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

    // MARK: - App Store Versions (management)

    func createAppStoreVersion(appID: String, versionString: String, platform: String = "IOS") async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "appStoreVersions",
                "attributes": ["versionString": versionString, "platform": platform],
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ],
            ]
        ]
        let response = try await post("/appStoreVersions", body: body)
        guard
            let d = response["data"] as? [String: Any],
            let id = d["id"] as? String
        else { throw LaunchpadError.invalidResponse }
        return id
    }

    func listAppStoreVersions(appID: String) async throws -> [[String: Any]] {
        let data = try await get("/apps/\(appID)/appStoreVersions?fields[appStoreVersions]=versionString,appStoreState,platform,createdDate&limit=10&sort=-createdDate")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getAppStoreVersionDetail(versionID: String) async throws -> [String: Any] {
        let data = try await get("/appStoreVersions/\(versionID)?include=appStoreVersionLocalizations,routingAppCoverage,appStoreVersionPhasedRelease")
        return data["data"] as? [String: Any] ?? [:]
    }

    func updateAppStoreVersion(versionID: String, versionString: String?, releaseType: String?, earliestReleaseDate: String?, usesNonExemptEncryption: Bool?) async throws {
        var attrs: [String: Any] = [:]
        if let versionString { attrs["versionString"] = versionString }
        if let releaseType { attrs["releaseType"] = releaseType }
        if let earliestReleaseDate { attrs["earliestReleaseDate"] = earliestReleaseDate }
        if let usesNonExemptEncryption { attrs["usesNonExemptEncryption"] = usesNonExemptEncryption }
        let body: [String: Any] = [
            "data": ["type": "appStoreVersions", "id": versionID, "attributes": attrs]
        ]
        _ = try await patch("/appStoreVersions/\(versionID)", body: body)
    }

    func deleteAppStoreVersion(versionID: String) async throws {
        try await delete("/appStoreVersions/\(versionID)")
    }

    // MARK: - Builds (TestFlight)

    func listBuilds(appID: String, limit: Int = 20) async throws -> [[String: Any]] {
        let data = try await get("/builds?filter[app]=\(appID)&fields[builds]=version,uploadedDate,processingState,minOsVersion,iconAssetToken&sort=-uploadedDate&limit=\(limit)&include=preReleaseVersion")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getBuild(buildID: String) async throws -> [String: Any] {
        let data = try await get("/builds/\(buildID)?include=preReleaseVersion,betaGroups")
        return data["data"] as? [String: Any] ?? [:]
    }

    func getBuildIcons(buildID: String) async throws -> [[String: Any]] {
        let data = try await get("/builds/\(buildID)/icons")
        return data["data"] as? [[String: Any]] ?? []
    }

    func resendBetaTestInvitation(testerID: String) async throws {
        let body: [String: Any] = [
            "data": ["type": "betaTesterInvitations", "relationships": [
                "betaTester": ["data": ["type": "betaTesters", "id": testerID]]
            ]]
        ]
        _ = try await post("/betaTesterInvitations", body: body)
    }

    // MARK: - Sandbox Testers

    func listSandboxTesters() async throws -> [[String: Any]] {
        let data = try await get("/sandboxTesters?fields[sandboxTesters]=firstName,lastName,appleId,territory,subscriptionRenewalRate")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createSandboxTester(firstName: String, lastName: String, email: String, password: String, territory: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "sandboxTesters",
                "attributes": [
                    "firstName": firstName,
                    "lastName": lastName,
                    "appleId": email,
                    "password": password,
                    "territory": territory,
                ],
            ]
        ]
        let response = try await post("/sandboxTesters", body: body)
        guard
            let d = response["data"] as? [String: Any],
            let id = d["id"] as? String
        else { throw LaunchpadError.invalidResponse }
        return id
    }

    func deleteSandboxTester(id: String) async throws {
        try await delete("/sandboxTesters/\(id)")
    }

    func clearSandboxPurchases(testerID: String) async throws {
        _ = try await post("/sandboxTesters/\(testerID)/clearPurchaseHistory", body: [:])
    }

    func updateSandboxTesterRenewalRate(testerID: String, subscriptionRenewalRate: String) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "sandboxTesters",
                "id": testerID,
                "attributes": ["subscriptionRenewalRate": subscriptionRenewalRate],
            ]
        ]
        _ = try await patch("/sandboxTesters/\(testerID)", body: body)
    }

    // MARK: - Age Rating

    func getAgeRatingDeclaration(versionID: String) async throws -> [String: Any] {
        let data = try await get("/appStoreVersions/\(versionID)/ageRatingDeclaration")
        return data["data"] as? [String: Any] ?? [:]
    }

    // MARK: - Team (ASC Users)

    func listTeamUsers() async throws -> [[String: Any]] {
        let data = try await get("/users?fields[users]=username,firstName,lastName,roles,allAppsVisible&limit=50")
        return data["data"] as? [[String: Any]] ?? []
    }

    func inviteUser(email: String, firstName: String, lastName: String, roles: [String]) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "userInvitations",
                "attributes": [
                    "email": email,
                    "firstName": firstName,
                    "lastName": lastName,
                    "roles": roles,
                    "allAppsVisible": true,
                ],
            ]
        ]
        _ = try await post("/userInvitations", body: body)
    }

    func removeUser(userID: String) async throws {
        try await delete("/users/\(userID)")
    }

    func listUserInvitations() async throws -> [[String: Any]] {
        let data = try await get("/userInvitations?fields[userInvitations]=email,firstName,lastName,roles,expirationDate&limit=50")
        return data["data"] as? [[String: Any]] ?? []
    }

    func cancelUserInvitation(invitationID: String) async throws {
        try await delete("/userInvitations/\(invitationID)")
    }

    // MARK: - TestFlight Build Localizations

    func getBuildLocalizations(buildID: String) async throws -> [[String: Any]] {
        let data = try await get("/builds/\(buildID)/betaBuildLocalizations?fields[betaBuildLocalizations]=locale,whatsNew")
        return data["data"] as? [[String: Any]] ?? []
    }

    func updateBuildLocalization(localizationID: String, whatsNew: String) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "betaBuildLocalizations",
                "id": localizationID,
                "attributes": ["whatsNew": whatsNew],
            ]
        ]
        _ = try await patch("/betaBuildLocalizations/\(localizationID)", body: body)
    }

    func createBuildLocalization(buildID: String, locale: String, whatsNew: String) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "betaBuildLocalizations",
                "attributes": ["locale": locale, "whatsNew": whatsNew],
                "relationships": [
                    "build": ["data": ["type": "builds", "id": buildID]]
                ],
            ]
        ]
        _ = try await post("/betaBuildLocalizations", body: body)
    }

    // MARK: - TestFlight Beta Review Submission

    func submitForBetaReview(buildID: String) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "betaAppReviewSubmissions",
                "relationships": [
                    "build": ["data": ["type": "builds", "id": buildID]]
                ],
            ]
        ]
        _ = try await post("/betaAppReviewSubmissions", body: body)
    }

    func getBetaReviewStatus(buildID: String) async throws -> String {
        let data = try await get("/builds/\(buildID)/betaAppReviewSubmission?fields[betaAppReviewSubmissions]=betaReviewState")
        guard
            let d = data["data"] as? [String: Any],
            let attrs = d["attributes"] as? [String: Any],
            let state = attrs["betaReviewState"] as? String
        else { return "NOT_SUBMITTED" }
        return state
    }

    // MARK: - App Clips

    func getAppClips(appID: String) async throws -> [[String: Any]] {
        let data = try await get("/apps/\(appID)/appClips?fields[appClips]=bundleId")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getAppClipExperiences(appClipID: String) async throws -> [[String: Any]] {
        let data = try await get("/appClips/\(appClipID)/appClipDefaultExperiences?fields[appClipDefaultExperiences]=action,isPoweredBy")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getAppClipAdvancedExperiences(appClipID: String) async throws -> [[String: Any]] {
        let data = try await get("/appClips/\(appClipID)/appClipAdvancedExperiences?limit=50")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createAppClipAdvancedExperience(appClipID: String, invocationURL: String, placeID: String?, action: String) async throws -> String {
        var attrs: [String: Any] = ["invocationURL": invocationURL, "action": action, "isPoweredBy": false]
        if let placeID { attrs["placeID"] = placeID }
        let body: [String: Any] = [
            "data": [
                "type": "appClipAdvancedExperiences",
                "attributes": attrs,
                "relationships": ["appClip": ["data": ["type": "appClips", "id": appClipID]]],
            ]
        ]
        let response = try await post("/appClipAdvancedExperiences", body: body)
        guard let d = response["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteAppClipAdvancedExperience(experienceID: String) async throws {
        try await delete("/appClipAdvancedExperiences/\(experienceID)")
    }

    // MARK: - Build Beta Group Assignment

    func assignBuildToBetaGroups(buildID: String, groupIDs: [String]) async throws {
        let items = groupIDs.map { id -> [String: Any] in ["type": "betaGroups", "id": id] }
        let body: [String: Any] = ["data": items]
        _ = try await post("/builds/\(buildID)/relationships/betaGroups", body: body)
    }

    func removeBuildFromBetaGroups(buildID: String, groupIDs: [String]) async throws {
        let items = groupIDs.map { id -> [String: Any] in ["type": "betaGroups", "id": id] }
        let body: [String: Any] = ["data": items]
        try await delete("/builds/\(buildID)/relationships/betaGroups", body: body)
    }

    // MARK: - Beta License Agreements

    func getBetaLicenseAgreements(appID: String) async throws -> [String: Any] {
        let json = try await get("/apps/\(appID)/betaLicenseAgreement")
        return json["data"] as? [String: Any] ?? [:]
    }

    func updateBetaLicenseAgreement(agreementID: String, agreementText: String) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "betaLicenseAgreements",
                "id": agreementID,
                "attributes": ["agreementText": agreementText]
            ]
        ]
        _ = try await patch("/betaLicenseAgreements/\(agreementID)", body: body)
    }

    // MARK: - Product Page Optimization (A/B Experiments)

    func listAppStoreVersionExperiments(versionID: String) async throws -> [[String: Any]] {
        let json = try await get("/appStoreVersions/\(versionID)/appStoreVersionExperiments?limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    func createProductPageExperiment(versionID: String, name: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "appStoreVersionExperiments",
                "attributes": ["name": name],
                "relationships": [
                    "appStoreVersion": ["data": ["type": "appStoreVersions", "id": versionID]]
                ]
            ]
        ]
        let json = try await post("/appStoreVersionExperiments", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func startProductPageExperiment(experimentID: String) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "appStoreVersionExperiments",
                "id": experimentID,
                "attributes": ["started": true]
            ]
        ]
        _ = try await patch("/appStoreVersionExperiments/\(experimentID)", body: body)
    }

    func deleteProductPageExperiment(experimentID: String) async throws {
        try await delete("/appStoreVersionExperiments/\(experimentID)")
    }

    // MARK: - Alternative Distribution (EU)

    func listAlternativeDistributionPackages(appID: String) async throws -> [[String: Any]] {
        let json = try await get("/apps/\(appID)/alternativeDistributionPackages?limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    func listAlternativeDistributionDomains() async throws -> [[String: Any]] {
        let json = try await get("/alternativeDistributionDomains?limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    func createAlternativeDistributionDomain(referenceName: String, domain: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "alternativeDistributionDomains",
                "attributes": [
                    "referenceName": referenceName,
                    "domain": domain,
                ]
            ]
        ]
        let json = try await post("/alternativeDistributionDomains", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    // MARK: - App Review Attachments

    func listReviewAttachments(appStoreVersionID: String) async throws -> [[String: Any]] {
        let json = try await get("/appStoreVersions/\(appStoreVersionID)/appStoreReviewDetail?include=appStoreReviewAttachments")
        if let detail = json["data"] as? [String: Any],
           let included = json["included"] as? [[String: Any]] {
            _ = detail
            return included.filter { $0["type"] as? String == "appStoreReviewAttachments" }
        }
        return []
    }

    func getOrCreateReviewDetail(appStoreVersionID: String) async throws -> String {
        let existing = try await get("/appStoreVersions/\(appStoreVersionID)/appStoreReviewDetail")
        if let detail = existing["data"] as? [String: Any], let id = detail["id"] as? String {
            return id
        }
        let body: [String: Any] = [
            "data": [
                "type": "appStoreReviewDetails",
                "relationships": [
                    "appStoreVersion": ["data": ["type": "appStoreVersions", "id": appStoreVersionID]]
                ]
            ]
        ]
        let json = try await post("/appStoreReviewDetails", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    // MARK: - CI Issues

    func listCIIssues(buildRunID: String) async throws -> [[String: Any]] {
        let json = try await get("/ciBuildRuns/\(buildRunID)/issues?limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    // MARK: - Export Compliance (Encryption Declarations)

    func listEncryptionDeclarations(appID: String) async throws -> [[String: Any]] {
        let json = try await get("/appEncryptionDeclarations?filter[app]=\(appID)&limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    func createEncryptionDeclaration(appID: String, platform: String, usesEncryption: Bool, exempt: Bool, containsProprietaryCryptography: Bool, containsThirdPartyCryptography: Bool, availableOnFrenchStore: Bool, documentURL: String?) async throws -> String {
        var attrs: [String: Any] = [
            "platform": platform,
            "usesEncryption": usesEncryption,
            "exempt": exempt,
            "containsProprietaryCryptography": containsProprietaryCryptography,
            "containsThirdPartyCryptography": containsThirdPartyCryptography,
            "availableOnFrenchStore": availableOnFrenchStore,
        ]
        if let url = documentURL { attrs["documentUrl"] = url }
        let body: [String: Any] = [
            "data": [
                "type": "appEncryptionDeclarations",
                "attributes": attrs,
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ]
            ]
        ]
        let json = try await post("/appEncryptionDeclarations", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    // MARK: - Xcode Cloud Artifacts & Test Results

    func listCIArtifacts(buildRunID: String) async throws -> [[String: Any]] {
        let json = try await get("/ciBuildRuns/\(buildRunID)/artifacts?limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    func listCITestResults(buildRunID: String) async throws -> [[String: Any]] {
        let json = try await get("/ciBuildRuns/\(buildRunID)/testResults?limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    // MARK: - Source Code Manager (SCM for Xcode Cloud)

    func listSCMProviders() async throws -> [[String: Any]] {
        let json = try await get("/scmProviders?limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    func listSCMRepositories(providerID: String) async throws -> [[String: Any]] {
        let json = try await get("/scmProviders/\(providerID)/repositories?limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    func listSCMGitReferences(repositoryID: String) async throws -> [[String: Any]] {
        let json = try await get("/scmRepositories/\(repositoryID)/gitReferences?limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    // MARK: - TestFlight App Localizations

    func getBetaAppLocalizations(appID: String) async throws -> [[String: Any]] {
        let json = try await get("/betaAppLocalizations?filter[app]=\(appID)&limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    func updateBetaAppLocalization(localizationID: String, description: String?, feedbackEmail: String?, marketingURL: String?, privacyPolicyURL: String?, tvOSPrivacyPolicy: String?) async throws {
        var attrs: [String: Any] = [:]
        if let d = description { attrs["description"] = d }
        if let e = feedbackEmail { attrs["feedbackEmail"] = e }
        if let u = marketingURL { attrs["marketingUrl"] = u }
        if let p = privacyPolicyURL { attrs["privacyPolicyUrl"] = p }
        if let t = tvOSPrivacyPolicy { attrs["tvOsPrivacyPolicy"] = t }
        let body: [String: Any] = [
            "data": [
                "type": "betaAppLocalizations",
                "id": localizationID,
                "attributes": attrs,
            ]
        ]
        _ = try await patch("/betaAppLocalizations/\(localizationID)", body: body)
    }

    func createBetaAppLocalization(appID: String, locale: String, description: String, feedbackEmail: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "betaAppLocalizations",
                "attributes": [
                    "locale": locale,
                    "description": description,
                    "feedbackEmail": feedbackEmail,
                ],
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ]
            ]
        ]
        let json = try await post("/betaAppLocalizations", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    // MARK: - CI Xcode Versions

    func listCIXcodeVersions() async throws -> [[String: Any]] {
        let json = try await get("/ciXcodeVersions?limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    func listCITestDestinations(xcodeVersionID: String) async throws -> [[String: Any]] {
        let json = try await get("/ciXcodeVersions/\(xcodeVersionID)/macOsVersions?limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    // MARK: - Xcode Cloud (CI)

    func listCIProducts(appID: String) async throws -> [[String: Any]] {
        let json = try await get("/ciProducts?filter[app]=\(appID)&limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    func listCIWorkflows(productID: String) async throws -> [[String: Any]] {
        let json = try await get("/ciProducts/\(productID)/workflows?limit=50")
        return json["data"] as? [[String: Any]] ?? []
    }

    func listCIBuilds(workflowID: String, limit: Int = 10) async throws -> [[String: Any]] {
        let json = try await get("/ciWorkflows/\(workflowID)/buildRuns?limit=\(limit)&sort=-createdDate")
        return json["data"] as? [[String: Any]] ?? []
    }

    func startCIBuild(workflowID: String, gitReferenceID: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "ciBuildRuns",
                "relationships": [
                    "workflow": ["data": ["type": "ciWorkflows", "id": workflowID]],
                    "sourceBranchOrTag": ["data": ["type": "scmGitReferences", "id": gitReferenceID]],
                ]
            ]
        ]
        let json = try await post("/ciBuildRuns", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    // MARK: - Beta Feedback

    func getBetaFeedback(appID: String, limit: Int = 20) async throws -> [[String: Any]] {
        let json = try await get("/betaFeedbacks?filter[tester.apps]=\(appID)&limit=\(limit)&sort=-timestamp")
        return json["data"] as? [[String: Any]] ?? []
    }

    func getBuildCrashes(buildID: String, limit: Int = 20) async throws -> [[String: Any]] {
        let json = try await get("/builds/\(buildID)/diagnosticSignatures?limit=\(limit)")
        return json["data"] as? [[String: Any]] ?? []
    }

    // MARK: - App Info Localizations

    func getAppInfoLocalizations(appInfoID: String) async throws -> [[String: Any]] {
        let json = try await get("/appInfos/\(appInfoID)/appInfoLocalizations?limit=200")
        return json["data"] as? [[String: Any]] ?? []
    }

    func updateAppInfoLocalization(localizationID: String, name: String?, subtitle: String?, privacyPolicyURL: String?, privacyPolicyText: String?) async throws {
        var attrs: [String: Any] = [:]
        if let n = name { attrs["name"] = n }
        if let s = subtitle { attrs["subtitle"] = s }
        if let u = privacyPolicyURL { attrs["privacyPolicyUrl"] = u }
        if let t = privacyPolicyText { attrs["privacyPolicyText"] = t }
        let body: [String: Any] = [
            "data": [
                "type": "appInfoLocalizations",
                "id": localizationID,
                "attributes": attrs,
            ]
        ]
        _ = try await patch("/appInfoLocalizations/\(localizationID)", body: body)
    }

    func createAppInfoLocalization(appInfoID: String, locale: String, name: String?, subtitle: String?, privacyPolicyURL: String?) async throws -> String {
        var attrs: [String: Any] = ["locale": locale]
        if let n = name { attrs["name"] = n }
        if let s = subtitle { attrs["subtitle"] = s }
        if let u = privacyPolicyURL { attrs["privacyPolicyUrl"] = u }
        let body: [String: Any] = [
            "data": [
                "type": "appInfoLocalizations",
                "attributes": attrs,
                "relationships": [
                    "appInfo": ["data": ["type": "appInfos", "id": appInfoID]]
                ],
            ]
        ]
        let resp = try await post("/appInfoLocalizations", body: body)
        guard let d = resp["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteAppInfoLocalization(localizationID: String) async throws {
        try await delete("/appInfoLocalizations/\(localizationID)")
    }

    // MARK: - Review Submissions

    func createReviewSubmission(appID: String, platform: String = "IOS") async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "reviewSubmissions",
                "attributes": ["platform": platform],
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ],
            ]
        ]
        let resp = try await post("/reviewSubmissions", body: body)
        guard let d = resp["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func cancelReviewSubmission(submissionID: String) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "reviewSubmissions",
                "id": submissionID,
                "attributes": ["canceled": true],
            ]
        ]
        _ = try await patch("/reviewSubmissions/\(submissionID)", body: body)
    }

    // MARK: - App Categories

    func getAppInfo(appID: String) async throws -> [String: Any] {
        let data = try await get("/apps/\(appID)/appInfos?include=primaryCategory,secondaryCategory&limit=1")
        guard let infos = data["data"] as? [[String: Any]] else { throw LaunchpadError.invalidResponse }
        return infos.first ?? [:]
    }

    func updateAppInfo(appInfoID: String, primaryLocale: String?, primaryCategoryID: String?, secondaryCategoryID: String?) async throws {
        var attrs: [String: Any] = [:]
        if let primaryLocale { attrs["primaryLocale"] = primaryLocale }
        var rels: [String: Any] = [:]
        if let cat = primaryCategoryID {
            rels["primaryCategory"] = ["data": ["type": "appCategories", "id": cat]]
        }
        if let cat = secondaryCategoryID {
            rels["secondaryCategory"] = ["data": ["type": "appCategories", "id": cat]]
        }
        var dataBody: [String: Any] = ["type": "appInfos", "id": appInfoID]
        if !attrs.isEmpty { dataBody["attributes"] = attrs }
        if !rels.isEmpty  { dataBody["relationships"] = rels }
        let body: [String: Any] = ["data": dataBody]
        _ = try await patch("/appInfos/\(appInfoID)", body: body)
    }

    // MARK: - IAP Localizations

    func listIAPLocalizations(iapID: String) async throws -> [[String: Any]] {
        let data = try await get("/inAppPurchasesV2/\(iapID)/inAppPurchaseLocalizations")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createIAPLocalization(iapID: String, locale: String, name: String, description: String?) async throws -> String {
        var attrs: [String: Any] = ["locale": locale, "name": name]
        if let description { attrs["description"] = description }
        let body: [String: Any] = [
            "data": [
                "type": "inAppPurchaseLocalizations",
                "attributes": attrs,
                "relationships": [
                    "inAppPurchaseV2": ["data": ["type": "inAppPurchases", "id": iapID]]
                ],
            ]
        ]
        let response = try await post("/inAppPurchaseLocalizations", body: body)
        guard let d = response["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func updateIAPLocalization(localizationID: String, name: String?, description: String?) async throws {
        var attrs: [String: Any] = [:]
        if let name        { attrs["name"] = name }
        if let description { attrs["description"] = description }
        let body: [String: Any] = [
            "data": ["type": "inAppPurchaseLocalizations", "id": localizationID, "attributes": attrs]
        ]
        _ = try await patch("/inAppPurchaseLocalizations/\(localizationID)", body: body)
    }

    func deleteIAPLocalization(localizationID: String) async throws {
        try await delete("/inAppPurchaseLocalizations/\(localizationID)")
    }

    // MARK: - Screenshot Set Management

    func createScreenshotSet(localizationID: String, screenshotDisplayType: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "appScreenshotSets",
                "attributes": ["screenshotDisplayType": screenshotDisplayType],
                "relationships": [
                    "appStoreVersionLocalization": ["data": ["type": "appStoreVersionLocalizations", "id": localizationID]]
                ],
            ]
        ]
        let response = try await post("/appScreenshotSets", body: body)
        guard let d = response["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteScreenshotSet(setID: String) async throws {
        try await delete("/appScreenshotSets/\(setID)")
    }

    // MARK: - In-App Purchases (ASC API)

    func listInAppPurchases(appID: String) async throws -> [[String: Any]] {
        let json = try await get("/apps/\(appID)/inAppPurchasesV2?limit=200&fields[inAppPurchases]=name,productID,inAppPurchaseType,state")
        return json["data"] as? [[String: Any]] ?? []
    }

    func getInAppPurchase(iapID: String) async throws -> [String: Any] {
        let json = try await get("/inAppPurchasesV2/\(iapID)")
        return json["data"] as? [String: Any] ?? [:]
    }

    func createInAppPurchase(appID: String, productID: String, name: String, iapType: String, reviewNote: String?) async throws -> String {
        var attrs: [String: Any] = [
            "productId": productID,
            "referenceName": name,
            "inAppPurchaseType": iapType,
        ]
        if let note = reviewNote { attrs["reviewNote"] = note }
        let body: [String: Any] = [
            "data": [
                "type": "inAppPurchases",
                "attributes": attrs,
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ]
            ]
        ]
        let json = try await post("/inAppPurchasesV2", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func updateInAppPurchase(iapID: String, name: String?, reviewNote: String?) async throws {
        var attrs: [String: Any] = [:]
        if let name { attrs["name"] = name }
        if let reviewNote { attrs["reviewNote"] = reviewNote }
        let body: [String: Any] = [
            "data": ["type": "inAppPurchases", "id": iapID, "attributes": attrs]
        ]
        _ = try await patch("/inAppPurchasesV2/\(iapID)", body: body)
    }

    func deleteInAppPurchase(iapID: String) async throws {
        try await delete("/inAppPurchasesV2/\(iapID)")
    }

    // MARK: - IAP Price Schedules

    func getIAPPriceSchedule(iapID: String) async throws -> [String: Any] {
        let data = try await get("/inAppPurchasesV2/\(iapID)/iapPriceSchedule?include=manualPrices,baseTerritory")
        return data["data"] as? [String: Any] ?? [:]
    }

    func listIAPPrices(iapID: String) async throws -> [[String: Any]] {
        let data = try await get("/inAppPurchasesV2/\(iapID)/iapPriceSchedule?include=manualPrices")
        guard let included = data["included"] as? [[String: Any]] else { return [] }
        return included.filter { $0["type"] as? String == "iapPrices" }
    }

    func setIAPPriceSchedule(iapID: String, pricePointID: String, startDate: String?) async throws {
        var manualPriceAttrs: [String: Any] = [:]
        if let startDate { manualPriceAttrs["startDate"] = startDate }
        let manualPrice: [String: Any] = [
            "type": "iapPrices",
            "attributes": manualPriceAttrs,
            "relationships": [
                "iapPricePoint": ["data": ["type": "iapPricePoints", "id": pricePointID]]
            ]
        ]
        let body: [String: Any] = [
            "data": [
                "type": "iapPriceSchedules",
                "relationships": [
                    "inAppPurchase": ["data": ["type": "inAppPurchases", "id": iapID]],
                    "manualPrices": ["data": [manualPrice]]
                ]
            ]
        ]
        _ = try await post("/iapPriceSchedules", body: body)
    }

    // MARK: - Subscription Availability & Prices

    func getSubscriptionAvailability(subscriptionID: String) async throws -> [String: Any] {
        let data = try await get("/subscriptions/\(subscriptionID)/subscriptionAvailability?include=availableTerritories")
        return data["data"] as? [String: Any] ?? [:]
    }

    func createSubscriptionAvailability(subscriptionID: String, availableInNewTerritories: Bool, territoryCodes: [String]) async throws -> String {
        let territories = territoryCodes.map { ["type": "territories", "id": $0] }
        let body: [String: Any] = [
            "data": [
                "type": "subscriptionAvailabilities",
                "attributes": ["availableInNewTerritories": availableInNewTerritories],
                "relationships": [
                    "subscription": ["data": ["type": "subscriptions", "id": subscriptionID]],
                    "availableTerritories": ["data": territories],
                ]
            ]
        ]
        let json = try await post("/subscriptionAvailabilities", body: body)
        guard let d = json["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func listSubscriptionPrices(subscriptionID: String) async throws -> [[String: Any]] {
        let data = try await get("/subscriptions/\(subscriptionID)/prices?include=subscriptionPricePoint&limit=200")
        return data["data"] as? [[String: Any]] ?? []
    }

    func listSubscriptionPricePoints(subscriptionID: String, territory: String?) async throws -> [[String: Any]] {
        var path = "/subscriptions/\(subscriptionID)/pricePoints?limit=200"
        if let territory { path += "&filter[territory]=\(territory)" }
        let data = try await get(path)
        return data["data"] as? [[String: Any]] ?? []
    }

    func createSubscriptionPrice(subscriptionID: String, pricePointID: String, territory: String, startDate: String?) async throws -> String {
        var attrs: [String: Any] = [:]
        if let startDate { attrs["startDate"] = startDate }
        let body: [String: Any] = [
            "data": [
                "type": "subscriptionPrices",
                "attributes": attrs,
                "relationships": [
                    "subscription": ["data": ["type": "subscriptions", "id": subscriptionID]],
                    "subscriptionPricePoint": ["data": ["type": "subscriptionPricePoints", "id": pricePointID]],
                    "territory": ["data": ["type": "territories", "id": territory]],
                ]
            ]
        ]
        let json = try await post("/subscriptionPrices", body: body)
        guard let d = json["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteSubscriptionPrice(priceID: String) async throws {
        try await delete("/subscriptionPrices/\(priceID)")
    }

    // MARK: - Subscription Localizations

    func listSubscriptionLocalizations(subscriptionID: String) async throws -> [[String: Any]] {
        let data = try await get("/subscriptions/\(subscriptionID)/subscriptionLocalizations")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createSubscriptionLocalization(subscriptionID: String, locale: String, name: String, description: String?) async throws -> String {
        var attrs: [String: Any] = ["locale": locale, "name": name]
        if let description { attrs["description"] = description }
        let body: [String: Any] = [
            "data": [
                "type": "subscriptionLocalizations",
                "attributes": attrs,
                "relationships": [
                    "subscription": ["data": ["type": "subscriptions", "id": subscriptionID]]
                ],
            ]
        ]
        let response = try await post("/subscriptionLocalizations", body: body)
        guard let d = response["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func updateSubscriptionLocalization(localizationID: String, name: String?, description: String?) async throws {
        var attrs: [String: Any] = [:]
        if let name        { attrs["name"] = name }
        if let description { attrs["description"] = description }
        let body: [String: Any] = [
            "data": ["type": "subscriptionLocalizations", "id": localizationID, "attributes": attrs]
        ]
        _ = try await patch("/subscriptionLocalizations/\(localizationID)", body: body)
    }

    func deleteSubscriptionLocalization(localizationID: String) async throws {
        try await delete("/subscriptionLocalizations/\(localizationID)")
    }

    // MARK: - Subscription Images

    func listSubscriptionImages(subscriptionID: String) async throws -> [[String: Any]] {
        let data = try await get("/subscriptions/\(subscriptionID)/subscriptionImages")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createSubscriptionImage(subscriptionID: String, filePath: String) async throws -> String {
        let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent

        let reserveBody: [String: Any] = [
            "data": [
                "type": "subscriptionImages",
                "attributes": [
                    "fileName": fileName,
                    "fileSize": fileData.count,
                ],
                "relationships": [
                    "subscription": ["data": ["type": "subscriptions", "id": subscriptionID]]
                ],
            ]
        ]
        let reserveResp = try await post("/subscriptionImages", body: reserveBody)
        guard
            let d = reserveResp["data"] as? [String: Any],
            let id = d["id"] as? String,
            let attrs = d["attributes"] as? [String: Any],
            let uploadOps = attrs["uploadOperations"] as? [[String: Any]]
        else { throw LaunchpadError.invalidResponse }

        for op in uploadOps {
            guard let urlStr = op["url"] as? String,
                  let url = URL(string: urlStr),
                  let method = op["method"] as? String else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = method
            if let headers = op["requestHeaders"] as? [[String: String]] {
                for h in headers {
                    if let name = h["name"], let value = h["value"] { req.setValue(value, forHTTPHeaderField: name) }
                }
            }
            let offset = op["offset"] as? Int ?? 0
            let length = op["length"] as? Int ?? fileData.count
            req.httpBody = fileData.subdata(in: offset..<(offset + length))
            _ = try await URLSession.shared.data(for: req)
        }

        let commitBody: [String: Any] = [
            "data": ["type": "subscriptionImages", "id": id, "attributes": ["uploaded": true]]
        ]
        _ = try await patch("/subscriptionImages/\(id)", body: commitBody)
        return id
    }

    func deleteSubscriptionImage(imageID: String) async throws {
        try await delete("/subscriptionImages/\(imageID)")
    }

    // MARK: - Subscription Groups

    func getSubscriptionGroups(appID: String) async throws -> [[String: Any]] {
        let data = try await get("/subscriptionGroups?filter[app]=\(appID)&fields[subscriptionGroups]=referenceName")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createSubscriptionGroup(appID: String, referenceName: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "subscriptionGroups",
                "attributes": ["referenceName": referenceName],
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ]
            ]
        ]
        let json = try await post("/subscriptionGroups", body: body)
        guard let d = json["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteSubscriptionGroup(groupID: String) async throws {
        try await delete("/subscriptionGroups/\(groupID)")
    }

    func getSubscriptions(groupID: String) async throws -> [[String: Any]] {
        let data = try await get("/subscriptionGroups/\(groupID)/subscriptions?fields[subscriptions]=productID,name,state,subscriptionPeriod,reviewNote")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createSubscription(groupID: String, productID: String, name: String, period: String, reviewNote: String?) async throws -> String {
        var attrs: [String: Any] = [
            "productID": productID,
            "name": name,
            "subscriptionPeriod": period,
            "familySharable": false,
        ]
        if let reviewNote { attrs["reviewNote"] = reviewNote }
        let body: [String: Any] = [
            "data": [
                "type": "subscriptions",
                "attributes": attrs,
                "relationships": [
                    "group": ["data": ["type": "subscriptionGroups", "id": groupID]]
                ]
            ]
        ]
        let json = try await post("/subscriptions", body: body)
        guard let d = json["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteSubscription(subscriptionID: String) async throws {
        try await delete("/subscriptions/\(subscriptionID)")
    }

    // MARK: - Win-Back Offers

    func listWinBackOffers(subscriptionID: String) async throws -> [[String: Any]] {
        let data = try await get("/subscriptions/\(subscriptionID)/winBackOffers")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createWinBackOffer(subscriptionID: String, offerId: String, priority: String, customerEligibilityPaidSubscriptionDurationInMonths: Int, customerEligibilityTimeSinceLastSubscribedInMonths: Int, offerMode: String, duration: String, offerEligibility: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "winBackOffers",
                "attributes": [
                    "offerId": offerId,
                    "priority": priority,
                    "customerEligibility": [
                        "paidSubscriptionDurationInMonths": customerEligibilityPaidSubscriptionDurationInMonths,
                        "timeSinceLastSubscribedInMonths": ["minimum": customerEligibilityTimeSinceLastSubscribedInMonths],
                    ],
                    "offerMode": offerMode,
                    "duration": duration,
                    "offerEligibility": offerEligibility,
                    "startDate": nil as Any?,
                    "endDate": nil as Any?,
                ] as [String: Any?],
                "relationships": [
                    "subscription": ["data": ["type": "subscriptions", "id": subscriptionID]]
                ],
            ] as [String: Any]
        ]
        let response = try await post("/winBackOffers", body: body)
        guard let d = response["data"] as? [String: Any], let id = d["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteWinBackOffer(offerID: String) async throws {
        try await delete("/winBackOffers/\(offerID)")
    }

    // MARK: - Promo Codes

    func getPromoCodeOffers(appID: String) async throws -> [[String: Any]] {
        let data = try await get("/apps/\(appID)/appStoreVersions?filter[appStoreState]=READY_FOR_SALE&fields[appStoreVersions]=versionString")
        return data["data"] as? [[String: Any]] ?? []
    }

    func createPromoCodes(appID: String, quantity: Int) async throws -> [[String: Any]] {
        let body: [String: Any] = [
            "data": [
                "type": "appPromotionalOfferCodes",
                "attributes": ["numberOfCodes": quantity],
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ],
            ]
        ]
        let response = try await post("/appPromoCodes", body: body)
        return (response["data"] as? [[String: Any]]) ?? []
    }

    func listPromoCodes(appID: String) async throws -> [[String: Any]] {
        let data = try await get("/apps/\(appID)/promoCodes?limit=20")
        return data["data"] as? [[String: Any]] ?? []
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

    // MARK: - Sales Reports

    func downloadSalesReport(vendorNumber: String, reportType: String, reportSubType: String, frequency: String, reportDate: String) async throws -> String {
        let path = "/salesReports?filter[frequency]=\(frequency)&filter[reportDate]=\(reportDate)&filter[reportSubType]=\(reportSubType)&filter[reportType]=\(reportType)&filter[vendorNumber]=\(vendorNumber)"
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try credentials.generateJWT())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try checkStatus(response, data)
        return String(data: data, encoding: .utf8) ?? ""
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

    // MARK: - Routing App Coverage

    func getRoutingAppCoverage(versionID: String) async throws -> [String: Any]? {
        let data = try await get("/appStoreVersions/\(versionID)/routingAppCoverage")
        return data["data"] as? [String: Any]
    }

    func uploadRoutingAppCoverage(versionID: String, filePath: String) async throws -> String {
        let fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent

        let reserveBody: [String: Any] = [
            "data": [
                "type": "routingAppCoverages",
                "attributes": [
                    "fileName": fileName,
                    "fileSize": fileData.count,
                ],
                "relationships": [
                    "appStoreVersion": ["data": ["type": "appStoreVersions", "id": versionID]]
                ],
            ]
        ]
        let reserveResp = try await post("/routingAppCoverages", body: reserveBody)
        guard
            let d = reserveResp["data"] as? [String: Any],
            let id = d["id"] as? String,
            let attrs = d["attributes"] as? [String: Any],
            let uploadOps = attrs["uploadOperations"] as? [[String: Any]]
        else { throw LaunchpadError.invalidResponse }

        for op in uploadOps {
            guard let urlStr = op["url"] as? String,
                  let url = URL(string: urlStr),
                  let method = op["method"] as? String else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = method
            if let headers = op["requestHeaders"] as? [[String: String]] {
                for h in headers {
                    if let name = h["name"], let value = h["value"] { req.setValue(value, forHTTPHeaderField: name) }
                }
            }
            let offset = op["offset"] as? Int ?? 0
            let length = op["length"] as? Int ?? fileData.count
            req.httpBody = fileData.subdata(in: offset..<(offset + length))
            _ = try await URLSession.shared.data(for: req)
        }

        let commitBody: [String: Any] = [
            "data": ["type": "routingAppCoverages", "id": id, "attributes": ["uploaded": true]]
        ]
        _ = try await patch("/routingAppCoverages/\(id)", body: commitBody)
        return id
    }

    func deleteRoutingAppCoverage(coverageID: String) async throws {
        try await delete("/routingAppCoverages/\(coverageID)")
    }

    // MARK: - App Review Detail (reviewer notes, demo account)

    func getReviewDetail(versionID: String) async throws -> [String: Any] {
        let data = try await get("/appStoreVersions/\(versionID)/appStoreReviewDetail")
        return data["data"] as? [String: Any] ?? [:]
    }

    func updateReviewDetail(
        detailID: String,
        notes: String?,
        demoAccountName: String?,
        demoAccountPassword: String?,
        demoAccountRequired: Bool?,
        contactFirstName: String?,
        contactLastName: String?,
        contactEmail: String?,
        contactPhone: String?
    ) async throws {
        var attrs: [String: Any] = [:]
        if let notes            { attrs["notes"] = notes }
        if let demoAccountName  { attrs["demoAccountName"] = demoAccountName }
        if let demoAccountPassword { attrs["demoAccountPassword"] = demoAccountPassword }
        if let demoAccountRequired { attrs["demoAccountRequired"] = demoAccountRequired }
        if let contactFirstName { attrs["contactFirstName"] = contactFirstName }
        if let contactLastName  { attrs["contactLastName"] = contactLastName }
        if let contactEmail     { attrs["contactEmail"] = contactEmail }
        if let contactPhone     { attrs["contactPhone"] = contactPhone }
        let body: [String: Any] = [
            "data": ["type": "appStoreReviewDetails", "id": detailID, "attributes": attrs]
        ]
        _ = try await patch("/appStoreReviewDetails/\(detailID)", body: body)
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

    // MARK: - Territories Reference

    func listAllTerritories() async throws -> [[String: Any]] {
        let json = try await get("/territories?limit=200")
        return json["data"] as? [[String: Any]] ?? []
    }

    // MARK: - App Availability

    func setAvailableTerritories(appID: String, territoryCodes: [String]) async throws {
        let items = territoryCodes.map { code -> [String: Any] in
            ["type": "territories", "id": code]
        }
        let body: [String: Any] = ["data": items]
        _ = try await patch("/apps/\(appID)/relationships/availableTerritories", body: body)
    }

    // MARK: - Price Points

    func listPricePoints(appID: String, territory: String? = nil) async throws -> [[String: Any]] {
        var path = "/apps/\(appID)/appPricePoints?limit=200"
        if let t = territory { path += "&filter[territory]=\(t)" }
        let json = try await get(path)
        return json["data"] as? [[String: Any]] ?? []
    }

    func listPriceTiers() async throws -> [[String: Any]] {
        let json = try await get("/appPriceTiers?limit=200")
        return json["data"] as? [[String: Any]] ?? []
    }

    // MARK: - API Keys

    func listAPIKeys() async throws -> [[String: Any]] {
        let json = try await get("/apiKeys?limit=200")
        return json["data"] as? [[String: Any]] ?? []
    }

    func createAPIKey(name: String, roles: [String]) async throws -> [String: Any] {
        let body: [String: Any] = [
            "data": [
                "type": "apiKeys",
                "attributes": [
                    "nickname": name,
                    "roles": roles,
                ]
            ]
        ]
        let json = try await post("/apiKeys", body: body)
        return json["data"] as? [String: Any] ?? [:]
    }

    func revokeAPIKey(keyID: String) async throws {
        try await delete("/apiKeys/\(keyID)")
    }

    // MARK: - EULA (End User License Agreements)

    func listEULAs() async throws -> [[String: Any]] {
        let json = try await get("/endUserLicenseAgreements")
        return json["data"] as? [[String: Any]] ?? []
    }

    func getEULA(eulaID: String) async throws -> [String: Any] {
        let json = try await get("/endUserLicenseAgreements/\(eulaID)")
        return json["data"] as? [String: Any] ?? [:]
    }

    func createEULA(appID: String, agreementText: String, territories: [String]) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "endUserLicenseAgreements",
                "attributes": [
                    "agreementText": agreementText,
                    "territories": territories,
                ],
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ]
            ]
        ]
        let json = try await post("/endUserLicenseAgreements", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func updateEULA(eulaID: String, agreementText: String, territories: [String]) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "endUserLicenseAgreements",
                "id": eulaID,
                "attributes": [
                    "agreementText": agreementText,
                    "territories": territories,
                ]
            ]
        ]
        _ = try await patch("/endUserLicenseAgreements/\(eulaID)", body: body)
    }

    func deleteEULA(eulaID: String) async throws {
        try await delete("/endUserLicenseAgreements/\(eulaID)")
    }

    // MARK: - Pre-Order

    func getPreOrder(appID: String) async throws -> [String: Any] {
        let json = try await get("/apps/\(appID)/preOrder")
        return json["data"] as? [String: Any] ?? [:]
    }

    func createPreOrder(appID: String, availableDate: String) async throws {
        let body: [String: Any] = [
            "data": [
                "type": "appPreOrders",
                "attributes": [
                    "appReleaseDate": availableDate,
                ],
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ]
            ]
        ]
        _ = try await post("/appPreOrders", body: body)
    }

    func cancelPreOrder(preOrderID: String) async throws {
        try await delete("/appPreOrders/\(preOrderID)")
    }

    // MARK: - Game Center

    func listLeaderboards(appID: String) async throws -> [[String: Any]] {
        let json = try await get("/gameCenterLeaderboards?filter[app]=\(appID)&limit=200")
        return json["data"] as? [[String: Any]] ?? []
    }

    func createLeaderboard(appID: String, referenceName: String, defaultFormatter: String, scoreSortType: String) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "gameCenterLeaderboards",
                "attributes": [
                    "referenceName": referenceName,
                    "vendorIdentifier": referenceName,
                    "defaultFormatter": defaultFormatter,
                    "scoreSortType": scoreSortType,
                ],
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ]
            ]
        ]
        let json = try await post("/gameCenterLeaderboards", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteLeaderboard(leaderboardID: String) async throws {
        try await delete("/gameCenterLeaderboards/\(leaderboardID)")
    }

    func listAchievements(appID: String) async throws -> [[String: Any]] {
        let json = try await get("/gameCenterAchievements?filter[app]=\(appID)&limit=200")
        return json["data"] as? [[String: Any]] ?? []
    }

    func createAchievement(appID: String, referenceName: String, points: Int, repeatable: Bool) async throws -> String {
        let body: [String: Any] = [
            "data": [
                "type": "gameCenterAchievements",
                "attributes": [
                    "referenceName": referenceName,
                    "vendorIdentifier": referenceName,
                    "points": points,
                    "repeatable": repeatable,
                    "showBeforeEarned": true,
                ],
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appID]]
                ]
            ]
        ]
        let json = try await post("/gameCenterAchievements", body: body)
        guard let data = json["data"] as? [String: Any], let id = data["id"] as? String else {
            throw LaunchpadError.invalidResponse
        }
        return id
    }

    func deleteAchievement(achievementID: String) async throws {
        try await delete("/gameCenterAchievements/\(achievementID)")
    }

    // MARK: - Performance / Power Metrics

    func getPerfPowerMetrics(buildID: String, metricTypes: [String]? = nil, deviceType: String? = nil) async throws -> [[String: Any]] {
        var params = "?limit=200"
        if let types = metricTypes, !types.isEmpty {
            params += "&filter[metricType]=" + types.joined(separator: ",")
        }
        if let device = deviceType {
            params += "&filter[deviceType]=\(device)"
        }
        let json = try await get("/builds/\(buildID)/perfPowerMetrics\(params)")
        return json["data"] as? [[String: Any]] ?? []
    }

    func getAppPerfPowerMetrics(appID: String, metricTypes: [String]? = nil, deviceType: String? = nil) async throws -> [[String: Any]] {
        var params = "?limit=200"
        if let types = metricTypes, !types.isEmpty {
            params += "&filter[metricType]=" + types.joined(separator: ",")
        }
        if let device = deviceType {
            params += "&filter[deviceType]=\(device)"
        }
        let json = try await get("/apps/\(appID)/perfPowerMetrics\(params)")
        return json["data"] as? [[String: Any]] ?? []
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
