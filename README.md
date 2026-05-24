# launchpad

fastlane の代替として作った iOS / Android リリース自動化 CLI です。  
App Store Connect API・Google Play Developer API・Apple Search Ads API を Swift で薄くラップし、日常のリリース作業をターミナル1行で完結させることを目的としています。

## 特徴

- **認証情報は環境変数で管理** — `.env` ファイルに書いておくだけで動く
- **設定ファイルで引数を省略** — `.launchpadrc` に書いたプロジェクト設定は毎回入力不要
- **iOS・Android を統一インターフェースで操作** — App Store Connect と Google Play の操作感を統一
- **ASO サポート** — キーワード順位チェック・メタデータ品質検査・レビュー集計が1コマンドで
- **リリースワンショット** — `launchpad release` でビルドから審査提出まで全自動

## 必要環境

- macOS 13 以上
- Xcode（iOS ビルドを行う場合）
- Swift 6.0 以上

## インストール

```bash
git clone https://github.com/entaku0818/launchpad.git
cd launchpad
make install
```

`/usr/local/bin/launchpad` にインストールされます。

アップデート時も同じコマンドで上書きインストールできます。

---

## セットアップ

### 1. テンプレートを生成する

プロジェクトのルートディレクトリで実行します。

```bash
launchpad init
```

`.launchpadrc`（プロジェクト設定）と `.env.template`（認証情報テンプレート）が生成されます。

### 2. 認証情報を設定する

```bash
cp .env.template .env
```

`.env` を開いて必要な値を埋めます。

```env
# App Store Connect API キー
# https://appstoreconnect.apple.com/access/api で発行
APP_STORE_CONNECT_API_KEY_KEY_ID=XXXXXXXXXX
APP_STORE_CONNECT_API_KEY_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
APP_STORE_CONNECT_API_KEY_CONTENT=-----BEGIN PRIVATE KEY-----\nMIGH...\n-----END PRIVATE KEY-----

# Android キーストア（リリースビルド時に必要）
KEYSTORE_PATH=/path/to/release.keystore
KEYSTORE_STORE_PASSWORD=your_password
KEYSTORE_KEY_ALIAS=your_alias
KEYSTORE_KEY_PASSWORD=your_key_password

# Google Play サービスアカウント
# Google Play Console → 設定 → API アクセス でサービスアカウントを作成
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"..."}
```

> **注意:** PEM キー（`APP_STORE_CONNECT_API_KEY_CONTENT`）の改行は `\n` でエスケープして1行で記述してください。`.env` は `.gitignore` に含まれているためコミットされません。

### 3. プロジェクト設定を記述する

`.launchpadrc` を編集します。

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

### 4. 動作確認

```bash
launchpad doctor
```

ツールの存在・環境変数・プロジェクトパスをまとめてチェックし、問題があれば修正方法を表示します。

---

## コマンドリファレンス

### ワンコマンドリリース

最もシンプルな使い方です。iOS と Android を同時にリリースします。

```bash
launchpad release
```

内部的には `build → upload → submit`（iOS）と `build → upload → promote`（Android）を順番に実行します。

```bash
# iOS のみリリース
launchpad release --ios

# ビルド済みの場合はビルドをスキップ
launchpad release --skip-build

# 実際には実行せず、何が行われるかだけ確認する
launchpad release --dry-run
```

---

### iOS

#### ビルド・アップロード・審査提出

```bash
# xcarchive を作成して IPA をエクスポート
launchpad ios build

# TestFlight または App Store にアップロード
launchpad ios upload

# 最新ビルドを審査に提出
launchpad ios submit

# バージョンを指定して審査提出
launchpad ios submit --version 1.2.0 --bundle-id com.example.app
```

#### メタデータ・スクリーンショット

`fastlane/metadata/` のディレクトリ構成（fastlane 互換）を読み込んで App Store に反映します。

```bash
# fastlane/metadata/ をすべての言語分 App Store に反映
launchpad ios metadata

# fastlane/screenshots/ のスクリーンショットをアップロード
launchpad ios screenshots
launchpad ios screenshots --overwrite   # 既存のものを削除してから上書き
```

#### バージョン番号の管理

```bash
# 現在のバージョンとビルド番号を表示
launchpad ios version-bump show

# パッチバージョンを上げる（例: 1.0.0 → 1.0.1）
launchpad ios version-bump version --patch

# マイナーバージョンを上げる（例: 1.0.0 → 1.1.0）
launchpad ios version-bump version --minor

# メジャーバージョンを上げる（例: 1.0.0 → 2.0.0）
launchpad ios version-bump version --major

# バージョン番号を直接指定する
launchpad ios version-bump version --set 2.0.0

# ビルド番号を自動インクリメント
launchpad ios version-bump build

# ビルド番号を直接指定する
launchpad ios version-bump build --set 100
```

#### TestFlight / Beta 管理

```bash
# Beta グループ一覧を表示
launchpad ios beta list

# テスターを追加
launchpad ios beta add-tester --email tester@example.com --group "External Testers"

# ビルド一覧を表示
launchpad ios builds list

# 特定ビルドのクラッシュレポートを確認
launchpad ios builds crashes --build-id XXXXXXXX
```

#### サブスクリプション・課金

```bash
# App 内課金アイテムの一覧
launchpad ios iap list

# サブスクリプショングループの一覧
launchpad ios subscription-groups list

# 特定トランザクションの購入履歴を確認（App Store Server API）
launchpad ios server-api history --original-transaction-id 123456789

# サブスクリプションの現在の状態を確認
launchpad ios server-api subscription --original-transaction-id 123456789

# 返金済みトランザクションの一覧
launchpad ios server-api refunds --original-transaction-id 123456789

# サーバー通知のテスト送信
launchpad ios server-api test-notification

# 通知履歴を取得
launchpad ios server-api notification-history \
  --start-date 1746748800000 --end-date 1746835200000
```

#### パフォーマンス計測・公証

```bash
# ビルド別のパフォーマンス指標（起動時間・メモリなど）
launchpad ios perf-metrics build --build-id XXXXXXXX

# アプリ全体のパフォーマンス指標
launchpad ios perf-metrics app --bundle-id com.example.app

# macOS アプリを Apple 公証に提出
launchpad ios notarize submit --file MyApp.dmg

# 公証の状態を確認
launchpad ios notarize status --submission-id XXXXXXXXXXXXXXXX

# 過去の公証申請一覧
launchpad ios notarize list

# 公証ログを取得（却下時のデバッグに）
launchpad ios notarize logs --submission-id XXXXXXXXXXXXXXXX
```

#### レビュー管理

```bash
# 最近のレビューを一覧表示
launchpad ios reviews list --limit 20

# レビューに返信する
launchpad ios reviews reply --review-id XXXX --body "ご報告ありがとうございます。次のバージョンで修正予定です。"

# 審査情報の確認・メモ更新
launchpad ios review-detail get --version-id XXXX
launchpad ios review-detail update --version-id XXXX --notes "審査メモ"
```

---

### Android

#### ビルド・アップロード・昇格

```bash
# Debug APK をビルド
launchpad android build

# 署名付き Release AAB をビルド（Keystore が必要）
launchpad android build --release

# Google Play の Internal テストトラックにアップロード
launchpad android upload --aab app-release.aab

# メタデータ（説明文・スクリーンショットなど）のみ更新
launchpad android upload --metadata-only

# Internal → Production に昇格（段階的リリース 10%）
launchpad android promote --from internal --to production --user-fraction 0.1

# Production に全量リリース
launchpad android promote --from internal --to production
```

#### バージョン番号の管理

```bash
# 現在の versionName と versionCode を表示
launchpad android version-bump show

# versionName を上げる（例: 1.0.0 → 1.0.1）
launchpad android version-bump version --patch
launchpad android version-bump version --minor
launchpad android version-bump version --major
launchpad android version-bump version --set 2.0.0

# versionCode を +1 する
launchpad android version-bump code

# versionCode を直接指定する
launchpad android version-bump code --set 150
```

#### レビュー・Vitals

```bash
# レビュー一覧
launchpad android reviews list

# レビューに返信
launchpad android reviews reply --review-id XXXX --text "ご意見ありがとうございます"

# クラッシュ率のトレンド
launchpad android vitals crashes \
  --package-name com.example.app \
  --start-date 2026-05-01 --end-date 2026-05-31

# ANR 率のトレンド
launchpad android vitals anr \
  --package-name com.example.app \
  --start-date 2026-05-01 --end-date 2026-05-31

# 異常検知アラート一覧
launchpad android vitals anomalies --package-name com.example.app
```

---

### ASO（App Store Optimization）

#### キーワード順位チェック

iTunes Search API（無料・認証不要）を使ってキーワード検索結果の順位を確認します。

```bash
launchpad ios aso keyword-rank \
  --bundle-id com.example.app \
  --keywords "英語学習,語学,TOEIC,英単語" \
  --country jp
```

出力例：
```
  🟢 #3   英語学習
  🟡 #24  TOEIC
  🔴 #87  語学
  ⬜ >200 英単語
```

#### キーワード候補の取得

Apple Search Ads の提案 API から、自社アプリまたは競合アプリに関連するキーワード候補とその推奨入札額を取得します。

```bash
# 自社アプリの Adam ID でキーワード候補を取得
launchpad ios aso keyword-suggestions --adam-id 123456789

# 競合アプリの Adam ID も加味した候補を取得
launchpad ios aso keyword-suggestions \
  --adam-id 123456789 \
  --competitor-ids 987654321 111222333
```

#### キーワードパフォーマンス分析

Search Ads のデータを ASO 視点で分析します。TTR・CVR・CPI を算出し、改善アドバイスを付けて表示します。

```bash
launchpad ios aso keyword-report \
  --campaign-id 12345 \
  --start-date 2026-05-01 \
  --end-date 2026-05-31
```

出力例（アドバイス付き）：
```
  英語学習              BROAD    3241   156    89   4200
    → High performer — add to keywords field
  grammar               EXACT     412    12     3    800
    → Low CVR (25.0%) — review store page
```

#### メタデータの品質チェック

`fastlane/metadata/` のファイルを App Store のルールに照らし合わせてチェックします。文字数オーバー・タイトルとキーワードの重複などを指摘します。

```bash
# iOS メタデータのチェック
launchpad ios aso metadata-check

# Android メタデータのチェック
launchpad android aso metadata-check
```

チェック内容（iOS）：
- タイトル: 30 文字以内
- サブタイトル: 30 文字以内
- キーワード: 100 バイト以内
- 説明文: 4,000 文字以内
- プロモーションテキスト: 170 文字以内
- タイトル・サブタイトルとキーワードの重複（枠の無駄遣い）

#### レビュー集計

最近のレビューを評価別に集計し、ポジティブ・ネガティブな頻出ワードを抽出します。

```bash
launchpad ios aso review-summary --bundle-id com.example.app --limit 200
launchpad android aso review-summary --package-name com.example.app
```

出力例：
```
  Reviews analyzed: 187  Average rating: 4.2 ★

  Rating distribution:
    5★  ████████████░░░░░░░░  98
    4★  ████░░░░░░░░░░░░░░░░  42
    3★  ██░░░░░░░░░░░░░░░░░░  18
    2★  █░░░░░░░░░░░░░░░░░░░   9
    1★  ██░░░░░░░░░░░░░░░░░░  20

  Frequently mentioned in low-rated reviews:
    "crash" ×14
    "slow"  ×9
```

---

### リリースノートの生成

git のコミット履歴からリリースノートを自動生成し、メタデータファイルに書き出します。

```bash
# 前回タグからの変更を確認（ファイルには書き出さない）
launchpad release-notes

# iOS・Android のすべてのロケールに書き出す
launchpad release-notes --ios --android --locale all

# 特定ロケールだけに書き出す
launchpad release-notes --ios --locale ja

# 特定タグからの範囲を指定する
launchpad release-notes --from v1.0.0 --to HEAD --ios --locale all
```

iOS は `fastlane/metadata/{locale}/release_notes.txt`、Android は `fastlane/metadata/android/{locale}/changelogs/default.txt` に書き出します。Android は自動的に 500 文字以内に切り詰めます。

---

### Apple Search Ads の管理

Search Ads の設定・運用を CLI で完結させます。別途 `SEARCH_ADS_*` 環境変数の設定が必要です。

```bash
# キャンペーン一覧
launchpad ios search-ads campaigns list

# キャンペーンを作成
launchpad ios search-ads campaigns create \
  --name "夏の英語キャンペーン" \
  --app-adam-id 123456789 \
  --budget 50000 \
  --currency JPY \
  --countries JP

# キーワードを追加
launchpad ios search-ads keywords add \
  --campaign-id 12345 \
  --ad-group-id 67890 \
  --keywords "英語学習" "英単語" "TOEIC対策" \
  --match-type BROAD

# 広告グループ別パフォーマンスレポート
launchpad ios search-ads report adgroups \
  --campaign-id 12345 \
  --start-date 2026-05-01 \
  --end-date 2026-05-31
```

---

## 環境変数一覧

| 変数名 | 説明 | 必要なコマンド |
|--------|------|----------------|
| `APP_STORE_CONNECT_API_KEY_KEY_ID` | ASC API キー ID | すべての `ios` コマンド |
| `APP_STORE_CONNECT_API_KEY_ISSUER_ID` | ASC 発行者 ID | すべての `ios` コマンド |
| `APP_STORE_CONNECT_API_KEY_CONTENT` | ASC 秘密鍵（PEM 形式） | すべての `ios` コマンド |
| `KEYSTORE_PATH` | Android キーストアのパス | `android build --release` |
| `KEYSTORE_STORE_PASSWORD` | キーストアのパスワード | `android build --release` |
| `KEYSTORE_KEY_ALIAS` | キーのエイリアス | `android build --release` |
| `KEYSTORE_KEY_PASSWORD` | キーのパスワード | `android build --release` |
| `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` | サービスアカウント JSON | すべての `android` コマンド |
| `SEARCH_ADS_CLIENT_ID` | Search Ads クライアント ID | `ios search-ads`, `ios aso keyword-*` |
| `SEARCH_ADS_TEAM_ID` | Search Ads チーム ID | 同上 |
| `SEARCH_ADS_KEY_ID` | Search Ads キー ID | 同上 |
| `SEARCH_ADS_PRIVATE_KEY_CONTENT` | Search Ads 秘密鍵（PEM 形式） | 同上 |
| `SEARCH_ADS_ORG_ID` | 組織 ID（複数組織の場合） | 同上（省略可） |
| `LAUNCHPAD_TELEMETRY_URL` | 利用状況の送信先 URL | 省略可 |
| `LAUNCHPAD_TELEMETRY_TOKEN` | テレメトリ認証トークン | 省略可 |

---

## ディレクトリ構成（メタデータ）

fastlane と互換性のあるディレクトリ構成を使用しています。

```
fastlane/
├── metadata/
│   ├── en-US/
│   │   ├── name.txt              # アプリ名（30文字以内）
│   │   ├── subtitle.txt          # サブタイトル（30文字以内）
│   │   ├── keywords.txt          # キーワード（100バイト以内、カンマ区切り）
│   │   ├── description.txt       # 説明文（4,000文字以内）
│   │   ├── promotional_text.txt  # プロモーションテキスト（170文字以内）
│   │   └── release_notes.txt     # リリースノート（4,000文字以内）
│   ├── ja/
│   │   └── ...
│   └── android/
│       ├── en-US/
│       │   ├── title.txt             # アプリ名（50文字以内）
│       │   ├── short_description.txt # 短い説明（80文字以内）
│       │   ├── full_description.txt  # 詳細（4,000文字以内）
│       │   └── changelogs/
│       │       └── default.txt       # 更新情報（500文字以内）
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

## ライセンス

MIT
