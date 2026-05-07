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

    // MARK: - Builds (TestFlight)

    func listBuilds(appID: String, limit: Int = 20) async throws -> [[String: Any]] {
        let data = try await get("/builds?filter[app]=\(appID)&fields[builds]=version,uploadedDate,processingState,minOsVersion,iconAssetToken&sort=-uploadedDate&limit=\(limit)&include=preReleaseVersion")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getBuild(buildID: String) async throws -> [String: Any] {
        let data = try await get("/builds/\(buildID)?include=preReleaseVersion,betaGroups")
        return data["data"] as? [String: Any] ?? [:]
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

    // MARK: - App Categories

    func getAppInfo(appID: String) async throws -> [String: Any] {
        let data = try await get("/apps/\(appID)/appInfos?include=primaryCategory,secondaryCategory&limit=1")
        guard let infos = data["data"] as? [[String: Any]] else { throw LaunchpadError.invalidResponse }
        return infos.first ?? [:]
    }

    // MARK: - Subscription Groups

    func getSubscriptionGroups(appID: String) async throws -> [[String: Any]] {
        let data = try await get("/subscriptionGroups?filter[app]=\(appID)&fields[subscriptionGroups]=referenceName")
        return data["data"] as? [[String: Any]] ?? []
    }

    func getSubscriptions(groupID: String) async throws -> [[String: Any]] {
        let data = try await get("/subscriptionGroups/\(groupID)/subscriptions?fields[subscriptions]=productID,name,state,subscriptionPeriod,reviewNote")
        return data["data"] as? [[String: Any]] ?? []
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
