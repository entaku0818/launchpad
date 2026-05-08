import ArgumentParser
import Foundation

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Check that required tools and environment variables are properly configured"
    )

    mutating func run() throws {
        DotEnv.load()
        let cfg = Config.load()

        var totalIssues = 0

        // MARK: Required tools

        printHeader("Required tools")
        let tools: [(cmd: String, args: [String], label: String)] = [
            ("xcodebuild", ["-version"],       "xcodebuild  (iOS builds)"),
            ("xcrun",      ["agvtool", "-v"],  "agvtool     (version bump)"),
            ("openssl",    ["version"],        "openssl     (Android JWT signing)"),
            ("git",        ["--version"],      "git         (release notes)"),
        ]
        for tool in tools {
            if let version = toolVersion(cmd: tool.cmd, args: tool.args) {
                ok(tool.label, detail: version)
            } else {
                fail(tool.label, detail: "not found in PATH")
                totalIssues += 1
            }
        }

        // MARK: Config files

        printHeader("Configuration files")
        let fm = FileManager.default

        if fm.fileExists(atPath: ".env") {
            ok(".env", detail: "found")
        } else {
            warn(".env", detail: "not found — run `launchpad init` to generate a template")
        }

        if fm.fileExists(atPath: ".launchpadrc") {
            ok(".launchpadrc", detail: "found")
        } else {
            warn(".launchpadrc", detail: "not found — run `launchpad init` to generate")
        }

        // MARK: iOS

        printHeader("iOS")

        let keyID     = env("APP_STORE_CONNECT_API_KEY_KEY_ID")
        let issuerID  = env("APP_STORE_CONNECT_API_KEY_ISSUER_ID")
        let keyContent = env("APP_STORE_CONNECT_API_KEY_CONTENT")

        checkEnv("KEY_ID      ", keyID,      "APP_STORE_CONNECT_API_KEY_KEY_ID", issues: &totalIssues)
        checkEnv("ISSUER_ID   ", issuerID,   "APP_STORE_CONNECT_API_KEY_ISSUER_ID", issues: &totalIssues)

        if let kc = keyContent, !kc.isEmpty {
            if kc.contains("BEGIN") {
                ok("KEY_CONTENT ", detail: "valid PEM")
            } else {
                fail("KEY_CONTENT ", detail: "set but doesn't look like a PEM key — check \\n escaping in .env")
                totalIssues += 1
            }
        } else {
            fail("KEY_CONTENT ", detail: "APP_STORE_CONNECT_API_KEY_CONTENT not set")
            totalIssues += 1
        }

        if let proj = cfg.ios?.project {
            if fm.fileExists(atPath: proj) {
                ok("ios.project ", detail: proj)
            } else {
                fail("ios.project ", detail: "path not found: \(proj)")
                totalIssues += 1
            }
        } else {
            warn("ios.project ", detail: "not set in .launchpadrc — required for build/upload")
        }

        if let bid = cfg.ios?.bundleId {
            ok("ios.bundleId", detail: bid)
        } else {
            warn("ios.bundleId", detail: "not set in .launchpadrc — required for most ios commands")
        }

        // MARK: Android

        printHeader("Android")

        let serviceAccount = env("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
        if let sa = serviceAccount, !sa.isEmpty {
            if let data = sa.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["private_key"] != nil {
                ok("SERVICE_ACCOUNT", detail: "valid JSON with private_key")
            } else {
                fail("SERVICE_ACCOUNT", detail: "set but not valid service account JSON")
                totalIssues += 1
            }
        } else {
            fail("SERVICE_ACCOUNT", detail: "GOOGLE_PLAY_SERVICE_ACCOUNT_JSON not set")
            totalIssues += 1
        }

        let keystorePath = env("KEYSTORE_PATH")
        if let ks = keystorePath, !ks.isEmpty {
            if fm.fileExists(atPath: ks) {
                ok("KEYSTORE_PATH  ", detail: ks)
            } else {
                fail("KEYSTORE_PATH  ", detail: "set but file not found: \(ks)")
                totalIssues += 1
            }
        } else {
            warn("KEYSTORE_PATH  ", detail: "KEYSTORE_PATH not set — required for android build --release")
        }

        checkEnv("KEYSTORE_PASS   ", env("KEYSTORE_STORE_PASSWORD"), "KEYSTORE_STORE_PASSWORD", required: false, issues: &totalIssues)
        checkEnv("KEYSTORE_ALIAS  ", env("KEYSTORE_KEY_ALIAS"),      "KEYSTORE_KEY_ALIAS",      required: false, issues: &totalIssues)

        if let dir = cfg.android?.projectDir {
            if fm.fileExists(atPath: dir) {
                ok("android.projectDir", detail: dir)
            } else {
                fail("android.projectDir", detail: "path not found: \(dir)")
                totalIssues += 1
            }
        } else {
            warn("android.projectDir", detail: "not set in .launchpadrc")
        }

        // MARK: Search Ads (optional)

        printHeader("Apple Search Ads (optional)")

        let searchAdsVars = [
            ("SEARCH_ADS_CLIENT_ID",           "CLIENT_ID     "),
            ("SEARCH_ADS_TEAM_ID",             "TEAM_ID       "),
            ("SEARCH_ADS_KEY_ID",              "KEY_ID        "),
            ("SEARCH_ADS_PRIVATE_KEY_CONTENT", "KEY_CONTENT   "),
        ]
        let searchAdsConfigured = searchAdsVars.allSatisfy { env($0.0) != nil }
        let searchAdsAny        = searchAdsVars.any { env($0.0) != nil }

        if searchAdsConfigured {
            for (varName, label) in searchAdsVars {
                ok(label, detail: varName)
            }
        } else if searchAdsAny {
            for (varName, label) in searchAdsVars {
                if env(varName) != nil {
                    ok(label, detail: varName)
                } else {
                    fail(label, detail: "\(varName) not set")
                    totalIssues += 1
                }
            }
        } else {
            skip("Search Ads", detail: "not configured — set SEARCH_ADS_* to enable `ios search-ads` commands")
        }

        // MARK: Telemetry (optional)

        printHeader("Telemetry (optional)")
        if let url = env("LAUNCHPAD_TELEMETRY_URL") {
            ok("TELEMETRY_URL", detail: url)
        } else {
            skip("TELEMETRY_URL", detail: "not set — set LAUNCHPAD_TELEMETRY_URL to track usage")
        }

        // MARK: Summary

        print("")
        if totalIssues == 0 {
            Logger.success("Everything looks good!")
        } else {
            Logger.warn("\(totalIssues) issue(s) found. Fix the items marked ✗ above before running release commands.")
        }
    }

    // MARK: - helpers

    private func toolVersion(cmd: String, args: [String]) -> String? {
        guard let output = try? Shell.run([cmd] + args) else { return nil }
        let first = output.components(separatedBy: "\n").first ?? output
        return first.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func env(_ key: String) -> String? {
        let v = ProcessInfo.processInfo.environment[key]
        return (v?.isEmpty == true) ? nil : v
    }

    private func checkEnv(_ label: String, _ value: String?, _ varName: String, required: Bool = true, issues: inout Int) {
        if let v = value, !v.isEmpty {
            ok(label, detail: varName)
        } else if required {
            fail(label, detail: "\(varName) not set")
            issues += 1
        } else {
            warn(label, detail: "\(varName) not set")
        }
    }

    private func printHeader(_ title: String) {
        print("\n\(title)")
        print(String(repeating: "-", count: title.count))
    }

    private func ok(_ label: String, detail: String) {
        print("  \u{001B}[32m✓\u{001B}[0m \(label)  \(detail)")
    }

    private func fail(_ label: String, detail: String) {
        print("  \u{001B}[31m✗\u{001B}[0m \(label)  \(detail)")
    }

    private func warn(_ label: String, detail: String) {
        print("  \u{001B}[33m⚠\u{001B}[0m \(label)  \(detail)")
    }

    private func skip(_ label: String, detail: String) {
        print("  \u{001B}[90m○\u{001B}[0m \(label)  \(detail)")
    }
}

private extension Array {
    func any(_ predicate: (Element) -> Bool) -> Bool {
        contains(where: predicate)
    }
}
