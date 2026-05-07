import ArgumentParser
import Foundation

struct IOSProvisioningCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "provisioning",
        abstract: "Manage devices, certificates, bundle IDs, and profiles",
        subcommands: [
            IOSDevicesListCommand.self,
            IOSDevicesRegisterCommand.self,
            IOSCertsListCommand.self,
            IOSCertsRevokeCommand.self,
            IOSBundleIDsListCommand.self,
            IOSBundleIDsRegisterCommand.self,
            IOSBundleIDsDeleteCommand.self,
            IOSBundleIDCapabilitiesListCommand.self,
            IOSBundleIDCapabilityEnableCommand.self,
            IOSBundleIDCapabilityDisableCommand.self,
            IOSProfilesListCommand.self,
            IOSProfilesDownloadCommand.self,
            IOSProfilesCreateCommand.self,
            IOSProfilesDeleteCommand.self,
        ]
    )
}

// MARK: - devices list

struct IOSDevicesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "devices",
        abstract: "List registered devices"
    )

    @Option(name: .long, help: "Max number of devices to show (default: 50)")
    var limit: Int = 50

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching registered devices")
        let devices = try await client.listDevices(limit: limit)

        if devices.isEmpty { Logger.info("No devices found"); return }

        Logger.info("\(devices.count) device(s)\n")
        for d in devices {
            guard let attrs = d["attributes"] as? [String: Any] else { continue }
            let name   = attrs["name"] as? String ?? "-"
            let udid   = attrs["udid"] as? String ?? "-"
            let cls    = attrs["deviceClass"] as? String ?? "-"
            let status = attrs["status"] as? String ?? "-"
            print("  \(name)  [\(cls)]  \(udid)  status: \(status)")
        }
    }
}

// MARK: - devices register

struct IOSDevicesRegisterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "register-device",
        abstract: "Register a new device"
    )

    @Option(name: .long, help: "Device name")
    var name: String

    @Option(name: .long, help: "Device UDID")
    var udid: String

    @Option(name: .long, help: "Platform (IOS or MAC_OS, default: IOS)")
    var platform: String = "IOS"

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Registering device '\(name)' (\(udid))")
        let id = try await client.registerDevice(name: name, udid: udid, platform: platform)
        Logger.success("Device registered  id: \(id)")
    }
}

// MARK: - certs list

struct IOSCertsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "certs",
        abstract: "List distribution certificates"
    )

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())

        Logger.step("Fetching certificates")
        let certs = try await client.listCertificates()

        if certs.isEmpty { Logger.info("No certificates found"); return }

        Logger.info("\(certs.count) certificate(s)\n")
        for c in certs {
            guard let id = c["id"] as? String,
                  let attrs = c["attributes"] as? [String: Any] else { continue }
            let name    = attrs["displayName"] as? String ?? attrs["name"] as? String ?? "-"
            let type_   = attrs["certificateType"] as? String ?? "-"
            let expires = attrs["expirationDate"] as? String ?? "-"
            print("  \(name)  [\(type_)]  expires: \(expires)  id: \(id)")
        }
    }
}

// MARK: - certs revoke

struct IOSCertsRevokeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "revoke-cert",
        abstract: "Revoke a certificate"
    )

    @Option(name: .long, help: "Certificate ID")
    var certificateID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Revoking certificate \(certificateID)")
        try await client.revokeCertificate(certificateID: certificateID)
        Logger.success("Certificate revoked")
    }
}

// MARK: - bundle IDs list

struct IOSBundleIDsListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "bundle-ids", abstract: "List registered bundle IDs")

    @Option(name: .long, help: "Max number to show (default: 50)")
    var limit: Int = 50

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching bundle IDs")
        let ids = try await client.listBundleIDs(limit: limit)

        if ids.isEmpty { Logger.info("No bundle IDs found"); return }
        Logger.info("\(ids.count) bundle ID(s)\n")
        for b in ids {
            guard let id = b["id"] as? String,
                  let attrs = b["attributes"] as? [String: Any] else { continue }
            let identifier = attrs["identifier"] as? String ?? "-"
            let name       = attrs["name"] as? String ?? "-"
            let platform   = attrs["platform"] as? String ?? "-"
            print("  \(identifier)  [\(platform)]  \(name)  id: \(id)")
        }
    }
}

// MARK: - bundle IDs register

struct IOSBundleIDsRegisterCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "register-bundle-id", abstract: "Register a new bundle ID")

    @Option(name: .long, help: "Bundle identifier (e.g. com.example.app)")
    var identifier: String

    @Option(name: .long, help: "Name for the bundle ID")
    var name: String

    @Option(name: .long, help: "Platform: IOS or MAC_OS (default: IOS)")
    var platform: String = "IOS"

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Registering bundle ID '\(identifier)'")
        let id = try await client.registerBundleID(identifier: identifier, name: name, platform: platform)
        Logger.success("Bundle ID registered: \(id)")
    }
}

// MARK: - bundle IDs delete

struct IOSBundleIDsDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete-bundle-id", abstract: "Delete a bundle ID")

    @Option(name: .long, help: "Bundle ID resource ID (from bundle-ids list)")
    var bundleIDResourceID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting bundle ID \(bundleIDResourceID)")
        try await client.deleteBundleID(bundleIDResourceID: bundleIDResourceID)
        Logger.success("Bundle ID deleted")
    }
}

// MARK: - bundle ID capabilities

struct IOSBundleIDCapabilitiesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "capabilities", abstract: "List capabilities enabled for a bundle ID")

    @Option(name: .long, help: "Bundle ID resource ID (from bundle-ids)")
    var bundleIDResourceID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching capabilities for bundle ID \(bundleIDResourceID)")
        let caps = try await client.listBundleIDCapabilities(bundleIDResourceID: bundleIDResourceID)

        if caps.isEmpty { Logger.info("No capabilities enabled"); return }
        Logger.info("\(caps.count) capability/capabilities enabled\n")
        for c in caps {
            guard let id = c["id"] as? String,
                  let attrs = c["attributes"] as? [String: Any] else { continue }
            let capType = attrs["capabilityType"] as? String ?? "-"
            print("  \(capType)  id: \(id)")
        }
    }
}

struct IOSBundleIDCapabilityEnableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "enable-capability", abstract: "Enable a capability for a bundle ID")

    @Option(name: .long, help: "Bundle ID resource ID (from bundle-ids)")
    var bundleIDResourceID: String

    @Option(name: .long, help: "Capability type, e.g. PUSH_NOTIFICATIONS, APPLE_PAY, IN_APP_PURCHASE, GAME_CENTER")
    var capability: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Enabling \(capability) for bundle ID \(bundleIDResourceID)")
        let id = try await client.enableBundleIDCapability(bundleIDResourceID: bundleIDResourceID, capabilityType: capability)
        Logger.success("Capability enabled: \(id)")
    }
}

struct IOSBundleIDCapabilityDisableCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "disable-capability", abstract: "Disable a capability for a bundle ID")

    @Option(name: .long, help: "Capability ID (from capabilities list)")
    var capabilityID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Disabling capability \(capabilityID)")
        try await client.disableBundleIDCapability(capabilityID: capabilityID)
        Logger.success("Capability disabled")
    }
}

// MARK: - profiles list

struct IOSProfilesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "profiles", abstract: "List provisioning profiles")

    @Option(name: .long, help: "Max number to show (default: 50)")
    var limit: Int = 50

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Fetching provisioning profiles")
        let profiles = try await client.listProfiles(limit: limit)

        if profiles.isEmpty { Logger.info("No profiles found"); return }
        Logger.info("\(profiles.count) profile(s)\n")
        for p in profiles {
            guard let id = p["id"] as? String,
                  let attrs = p["attributes"] as? [String: Any] else { continue }
            let name    = attrs["name"] as? String ?? "-"
            let type_   = attrs["profileType"] as? String ?? "-"
            let state   = attrs["profileState"] as? String ?? "-"
            let expires = attrs["expirationDate"] as? String ?? "-"
            print("  \(name)  [\(type_)]  state: \(state)  expires: \(expires)")
            print("    id: \(id)")
        }
    }
}

// MARK: - profiles download

struct IOSProfilesDownloadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "download-profile", abstract: "Download a provisioning profile (.mobileprovision)")

    @Option(name: .long, help: "Profile ID")
    var profileID: String

    @Option(name: .long, help: "Output file path (default: <profileID>.mobileprovision)")
    var output: String?

    mutating func run() async throws {
        DotEnv.load()
        let dest = output ?? "\(profileID).mobileprovision"
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Downloading profile \(profileID)")
        let data = try await client.downloadProfile(profileID: profileID)
        try data.write(to: URL(fileURLWithPath: dest))
        Logger.success("Profile saved to \(dest)")
    }
}

// MARK: - profiles create

struct IOSProfilesCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "create-profile", abstract: "Create a new provisioning profile")

    @Option(name: .long, help: "Profile display name")
    var name: String

    @Option(name: .long, help: "Profile type: IOS_APP_DEVELOPMENT, IOS_APP_STORE, IOS_APP_ADHOC, IOS_APP_INHOUSE")
    var profileType: String = "IOS_APP_STORE"

    @Option(name: .long, help: "Bundle ID resource ID (from bundle-ids)")
    var bundleIDResourceID: String

    @Option(name: .long, help: "Comma-separated certificate IDs (from certs)")
    var certificateIDs: String

    @Option(name: .long, help: "Comma-separated device IDs (from devices, required for DEVELOPMENT/ADHOC)")
    var deviceIDs: String = ""

    @Option(name: .long, help: "Output path for the .mobileprovision file (default: <name>.mobileprovision)")
    var output: String?

    mutating func run() async throws {
        DotEnv.load()
        let certList   = certificateIDs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let deviceList = deviceIDs.isEmpty ? [] : deviceIDs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Creating provisioning profile '\(name)' [\(profileType)]")
        let (id, profileData) = try await client.createProfile(
            name: name, profileType: profileType,
            bundleIDResourceID: bundleIDResourceID,
            certificateIDs: certList, deviceIDs: deviceList
        )
        let dest = output ?? "\(name.replacingOccurrences(of: " ", with: "_")).mobileprovision"
        try profileData.write(to: URL(fileURLWithPath: dest))
        Logger.success("Profile created: \(id)")
        Logger.info("Saved to \(dest)")
    }
}

// MARK: - profiles delete

struct IOSProfilesDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "delete-profile", abstract: "Delete a provisioning profile")

    @Option(name: .long, help: "Profile ID")
    var profileID: String

    mutating func run() async throws {
        DotEnv.load()
        let client = ASCAPIClient(credentials: try ASCCredentials.fromEnvironment())
        Logger.step("Deleting profile \(profileID)")
        try await client.deleteProfile(profileID: profileID)
        Logger.success("Profile deleted")
    }
}
