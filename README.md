# launchpad

Personal iOS/Android release tool. fastlane の代替として自作した Swift CLI。

## インストール

```bash
git clone https://github.com/entaku0818/launchpad.git
cd launchpad
make install   # /usr/local/bin/launchpad にインストール
```

## セットアップ

プロジェクトのルートで実行：

```bash
launchpad init
```

`.launchpadrc` と `.env.template` が生成されます。

### .launchpadrc

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

### .env

```env
APP_STORE_CONNECT_API_KEY_KEY_ID=XXXXXXXXXX
APP_STORE_CONNECT_API_KEY_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
APP_STORE_CONNECT_API_KEY_CONTENT=-----BEGIN PRIVATE KEY-----\n...

KEYSTORE_PATH=/path/to/release.keystore
KEYSTORE_STORE_PASSWORD=password
KEYSTORE_KEY_ALIAS=alias
KEYSTORE_KEY_PASSWORD=password

GOOGLE_PLAY_SERVICE_ACCOUNT_JSON={"type":"service_account",...}
```

## コマンド一覧

### iOS

```bash
# ビルド・アーカイブ・IPA生成
launchpad ios build

# TestFlight / App Store にアップロード
launchpad ios upload

# 審査提出
launchpad ios submit

# メタデータ更新 (fastlane/metadata/ を読み込む)
launchpad ios metadata

# スクリーンショット更新 (fastlane/screenshots/ を読み込む)
launchpad ios screenshots --overwrite
```

### Android

```bash
# Debug APK ビルド
launchpad android build

# Release AAB ビルド (keystore署名)
launchpad android build --release

# Google Play にアップロード
launchpad android upload --aab app-release.aab

# Internal → Production に昇格
launchpad android promote --from internal --to production

# メタデータのみ更新 (fastlane/metadata/android/ を読み込む)
launchpad android upload --metadata-only
```

## オプション省略

`.launchpadrc` に設定を書いておくと引数が省略できます。

```bash
# 引数なしで動く
launchpad ios submit
launchpad android build --release
```
