import ArgumentParser
import Foundation

struct IOSProvisioningCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "provisioning",
        abstract: "Manage devices and certificates",
        subcommands: [
            IOSDevicesListCommand.self,
            IOSDevicesRegisterCommand.self,
            IOSCertsListCommand.self,
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
            guard let attrs = c["attributes"] as? [String: Any] else { continue }
            let name    = attrs["displayName"] as? String ?? attrs["name"] as? String ?? "-"
            let type_   = attrs["certificateType"] as? String ?? "-"
            let expires = attrs["expirationDate"] as? String ?? "-"
            print("  \(name)  [\(type_)]  expires: \(expires)")
        }
    }
}
