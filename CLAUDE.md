# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

`launchpad` is a personal iOS/Android release CLI tool written in Swift, built as a fastlane alternative. It wraps `xcodebuild`, the App Store Connect API, and the Google Play Developer API into a single command.

## Build & Install

```bash
# Debug build
swift build

# Release build
swift build -c release

# Install to /usr/local/bin
make install

# Clean build artifacts
swift package clean
```

There are no automated tests in this project.

## Command Structure

The CLI is built with [swift-argument-parser](https://github.com/apple/swift-argument-parser) and follows this hierarchy:

```
launchpad
├── init                    # Generates .launchpadrc and .env.template
├── ios
│   ├── build               # xcodebuild archive + exportArchive → IPA
│   ├── upload              # altool upload to TestFlight/App Store
│   ├── submit              # Submit version for App Store review via ASC API
│   ├── metadata            # Push fastlane/metadata/ to ASC API
│   └── screenshots         # Push fastlane/screenshots/ to ASC API
└── android
    ├── build               # Gradle assembleDebug / bundleRelease
    ├── upload              # Google Play Edits API: upload AAB or metadata
    └── promote             # Promote a track (e.g. internal → production)
```

Every command calls `DotEnv.load()` first (reads `.env` in CWD), then `Config.load()` (reads `.launchpadrc` in CWD or `~/`).

## Core Architecture

### Configuration layer (`Core/`)

| File | Purpose |
|------|---------|
| `Config.swift` | Decodes `.launchpadrc` (JSON). Searched in CWD then `~/`. |
| `DotEnv.swift` | Loads `.env` into the process environment. Supports `\n` escaping for PEM keys. Does not overwrite existing env vars. |
| `Shell.swift` | Two helpers: `run()` captures stdout/stderr; `runLive()` inherits stdio for streaming output (used for long xcodebuild invocations). |
| `LaunchpadError.swift` | Typed error enum used throughout. |
| `Logger.swift` | Colored terminal output (step / info / success / error). |
| `XcodeProject.swift` | Reads `CFBundleShortVersionString` from a `.xcodeproj` plist. |

### iOS API layer

- `ASCAuth.swift` — `ASCCredentials` reads key ID, issuer ID, and PEM key content from env vars, generates ES256 JWT tokens (using CryptoKit `P256`), and writes `.p8` key files for altool compatibility.
- `ASCAPI.swift` — `ASCAPIClient` wraps the App Store Connect REST API v1. All HTTP methods return `[String: Any]` (raw JSONSerialization).

### Android API layer

- `GooglePlayClient.swift` — Handles OAuth2 (service account JWT → access token via `https://oauth2.googleapis.com/token`) and the Google Play Edits API. RSA signing for RS256 JWTs is done via a subprocess call to `openssl` (CryptoKit does not support RSA signing).

### Command option resolution pattern

All commands resolve options in priority order: CLI flag → `.launchpadrc` value → default. The pattern used throughout:

```swift
let value = cliOption ?? cfg?.field ?? "default"
```

## Environment Variables

iOS commands require:
- `APP_STORE_CONNECT_API_KEY_KEY_ID`
- `APP_STORE_CONNECT_API_KEY_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_CONTENT` (PEM content, `\n` escaped to one line in `.env`)

Android commands require:
- `KEYSTORE_PATH`, `KEYSTORE_STORE_PASSWORD`, `KEYSTORE_KEY_ALIAS`, `KEYSTORE_KEY_PASSWORD` (for `android build --release`)
- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` (full JSON blob of service account)

## Metadata file conventions

These match fastlane's directory layout:

- iOS metadata: `fastlane/metadata/{locale}/{description,keywords,release_notes,promotional_text,support_url,marketing_url}.txt`
- Android metadata: `fastlane/metadata/android/{locale}/{title,short_description,full_description}.txt` and `changelogs/default.txt`
- Screenshots: `fastlane/screenshots/{locale}/{display_type}/filename.png`
