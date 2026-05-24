# launchpad

A fastlane alternative for iOS/Android release automation, written in Swift.  
Wraps the App Store Connect API, Google Play Developer API, and Apple Search Ads API into a single unified CLI so that your entire release workflow fits in one terminal command.

> Japanese README: [README.md](README.md)

## Features

- **Credentials via environment variables** — write them once in `.env` and forget
- **Config file reduces repetition** — store project settings in `.launchpadrc` so you never re-type bundle IDs or scheme names
- **Unified interface for iOS and Android** — consistent command structure across both platforms
- **ASO built-in** — keyword rank checks, metadata quality lint, and review summaries in one command
- **One-shot release** — `launchpad release` runs build → upload → submit automatically

## Requirements

- macOS 13 or later
- Swift 6.0 or later
- Xcode (required for iOS builds)

## Installation

```bash
git clone https://github.com/entaku0818/launchpad.git
cd launchpad
make install
```

This installs `launchpad` to `/usr/local/bin/launchpad`. Re-run the same command to update.

---

## Setup

### 1. Generate templates

Run this in your project's root directory:

```bash
launchpad init
```

This creates `.launchpadrc` (project config) and `.env.template` (credentials template).

### 2. Fill in credentials

```bash
cp .env.template .env
```

Edit `.env` with your values:

```env
# App Store Connect API key
# Generate at: https://appstoreconnect.apple.com/access/api
APP_STORE_CONNECT_API_KEY_KEY_ID=XXXXXXXXXX
APP_STORE_CONNECT_API_KEY_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
APP_STORE_CONNECT_API_KEY_CONTENT=-----BEGIN PRIVATE KEY-----\nMIGH...\n-----END PRIVATE KEY-----

# Android keystore (required for release builds)
KEYSTORE_PATH=/path/to/release.keystore
KEYSTORE_STORE_PASSWORD=your_password
KEYSTORE_KEY_ALIAS=your_alias
KEYSTORE_KEY_PASSWORD=your_key_password

# Google Play service account
# Create at: Google Play Console → Setup → API access
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"..."}
```

> **Note:** The PEM key (`APP_STORE_CONNECT_API_KEY_CONTENT`) must have newlines escaped as `\n` so it fits on a single line. `.env` is listed in `.gitignore` and will not be committed.

### 3. Configure the project

Edit `.launchpadrc`:

```json
{
  "ios": {
    "project": "ios/App.xcodeproj",
    "scheme": "App",
    "bundleId": "com.example.app",
    "output": "./build",
    "exportMethod": "app-store"
  },
  "android": {
    "projectDir": "android/",
    "packageName": "com.example.app"
  }
}
```

### 4. Verify the setup

```bash
launchpad doctor
```

Checks tool availability, environment variables, and project paths — and tells you exactly what to fix if something is wrong.

---

## Command Reference

### One-shot release

```bash
launchpad release            # iOS + Android
launchpad release --ios      # iOS only
launchpad release --skip-build   # skip the build step
launchpad release --dry-run  # preview what would run
```

---

### iOS

#### Build · Upload · Submit

```bash
launchpad ios build
launchpad ios upload
launchpad ios submit
launchpad ios submit --version 1.2.0 --bundle-id com.example.app
```

#### Metadata & Screenshots

Uses the same directory layout as fastlane:

```bash
launchpad ios metadata              # push fastlane/metadata/ to App Store
launchpad ios screenshots           # push fastlane/screenshots/
launchpad ios screenshots --overwrite
```

#### Version bumping

```bash
launchpad ios version-bump show
launchpad ios version-bump version --patch   # 1.0.0 → 1.0.1
launchpad ios version-bump version --minor   # 1.0.0 → 1.1.0
launchpad ios version-bump version --major   # 1.0.0 → 2.0.0
launchpad ios version-bump version --set 2.0.0
launchpad ios version-bump build             # auto-increment
launchpad ios version-bump build --set 100
```

#### App Store version management

```bash
launchpad ios versions list
launchpad ios versions update --version-id XXXX --copyright "2026 Your Name"
launchpad ios age-rating get
launchpad ios age-rating set-clean           # set everything to 4+ (no content flags)
launchpad ios categories get
launchpad ios categories set --primary UTILITIES
launchpad ios pricing show
launchpad ios pricing set-free
launchpad ios app-info set-content-rights    # mark as not using third-party content
```

#### TestFlight / Beta

```bash
launchpad ios beta list
launchpad ios beta add-tester --email tester@example.com --group "External Testers"
launchpad ios builds list
launchpad ios builds crashes --build-id XXXXXXXX
```

#### Subscriptions & IAP

```bash
launchpad ios iap list
launchpad ios subscription-groups list
launchpad ios server-api history --original-transaction-id 123456789
launchpad ios server-api subscription --original-transaction-id 123456789
```

#### Reviews

```bash
launchpad ios reviews list --limit 20
launchpad ios reviews reply --review-id XXXX --body "Thank you for the feedback!"
launchpad ios review-detail get --version-id XXXX
```

#### Performance & Notarization

```bash
launchpad ios perf-metrics build --build-id XXXXXXXX
launchpad ios notarize submit --file MyApp.dmg
launchpad ios notarize status --submission-id XXXXXXXXXXXXXXXX
```

---

### Android

#### Build · Upload · Promote

```bash
launchpad android build                       # debug APK
launchpad android build --release             # signed release AAB
launchpad android upload --aab app-release.aab
launchpad android upload --metadata-only
launchpad android promote --from internal --to production --user-fraction 0.1
launchpad android promote --from internal --to production
```

#### Version bumping

```bash
launchpad android version-bump show
launchpad android version-bump version --patch
launchpad android version-bump code           # versionCode +1
launchpad android version-bump code --set 150
```

#### Reviews & Vitals

```bash
launchpad android reviews list
launchpad android reviews reply --review-id XXXX --text "Thanks for the report!"
launchpad android vitals crashes --package-name com.example.app \
  --start-date 2026-05-01 --end-date 2026-05-31
launchpad android vitals anomalies --package-name com.example.app
```

---

### ASO (App Store Optimization)

```bash
# Keyword rank check (uses iTunes Search API — no auth required)
launchpad ios aso keyword-rank \
  --bundle-id com.example.app \
  --keywords "language learning,TOEIC,vocabulary" \
  --country us

# Keyword suggestions from Apple Search Ads
launchpad ios aso keyword-suggestions --adam-id 123456789

# Metadata quality lint
launchpad ios aso metadata-check
launchpad android aso metadata-check

# Review summary
launchpad ios aso review-summary --bundle-id com.example.app --limit 200
launchpad android aso review-summary --package-name com.example.app
```

---

### Release notes generation

```bash
launchpad release-notes                          # preview only
launchpad release-notes --ios --android --locale all   # write to all locales
launchpad release-notes --ios --locale en-US
launchpad release-notes --from v1.0.0 --to HEAD --ios --locale all
```

iOS writes to `fastlane/metadata/{locale}/release_notes.txt`.  
Android writes to `fastlane/metadata/android/{locale}/changelogs/default.txt` (auto-truncated to 500 chars).

---

## Environment Variables

| Variable | Description | Required by |
|----------|-------------|-------------|
| `APP_STORE_CONNECT_API_KEY_KEY_ID` | ASC API key ID | all `ios` commands |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | ASC issuer ID | all `ios` commands |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | ASC private key (PEM, `\n`-escaped) | all `ios` commands |
| `KEYSTORE_PATH` | Path to Android keystore | `android build --release` |
| `KEYSTORE_STORE_PASSWORD` | Keystore password | `android build --release` |
| `KEYSTORE_KEY_ALIAS` | Key alias | `android build --release` |
| `KEYSTORE_KEY_PASSWORD` | Key password | `android build --release` |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | Full service account JSON blob | all `android` commands |
| `SEARCH_ADS_CLIENT_ID` | Search Ads client ID | `ios search-ads`, `ios aso keyword-*` |
| `SEARCH_ADS_TEAM_ID` | Search Ads team ID | same |
| `SEARCH_ADS_KEY_ID` | Search Ads key ID | same |
| `SEARCH_ADS_PRIVATE_KEY_CONTENT` | Search Ads private key (PEM) | same |
| `SEARCH_ADS_ORG_ID` | Org ID (multi-org only) | same (optional) |
| `LAUNCHPAD_TELEMETRY_URL` | Endpoint for usage telemetry | optional |
| `LAUNCHPAD_TELEMETRY_TOKEN` | Auth token for telemetry | optional |

---

## Metadata Directory Layout

Compatible with fastlane's metadata directory structure:

```
fastlane/
├── metadata/
│   ├── en-US/
│   │   ├── name.txt              # App name (≤30 chars)
│   │   ├── subtitle.txt          # Subtitle (≤30 chars)
│   │   ├── keywords.txt          # Keywords (≤100 bytes, comma-separated)
│   │   ├── description.txt       # Description (≤4,000 chars)
│   │   ├── promotional_text.txt  # Promotional text (≤170 chars)
│   │   └── release_notes.txt     # What's New (≤4,000 chars)
│   ├── ja/
│   │   └── ...
│   └── android/
│       ├── en-US/
│       │   ├── title.txt             # App name (≤50 chars)
│       │   ├── short_description.txt # Short description (≤80 chars)
│       │   ├── full_description.txt  # Full description (≤4,000 chars)
│       │   └── changelogs/
│       │       └── default.txt       # Release notes (≤500 chars)
│       └── ja-JP/
│           └── ...
└── screenshots/
    ├── en-US/
    │   ├── iPhone65/
    │   │   └── 01_home.png
    │   └── iPad/
    │       └── 01_home.png
    └── ja/
        └── ...
```

## License

MIT
