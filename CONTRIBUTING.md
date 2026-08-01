# Contributing

## CI について

このリポジトリには GitHub Actions の CI ジョブはありません。

`Package.swift` は `platforms: [.macOS(.v13)]` を指定しており、`CryptoKit` / `xcodebuild` /
`altool` といった Apple プラットフォーム専用の API・ツールに依存しているため、
ビルドと Lint は macOS 上でしか実行できません。GitHub Actions の macOS ランナー
（`macos-15`）は Linux ランナーに対して課金レートが高いため、CI を廃止して
**ローカルでの実行に統一**しています。

そのため、**コミット前に手元で下記のチェックを必ず実行してください。**

## コミット前チェック

```bash
# 1. ビルドが通ることを確認
swift build

# 2. Lint が通ることを確認（警告も許さない）
swiftlint lint --strict
```

両方が成功していることを確認してからコミット・PR を作成してください。
`swift build` は `Build complete!`、`swiftlint lint --strict` は
`Found 0 violations, 0 serious` になるのが正常な状態です。

このプロジェクトには自動テストはありません。実際のリリースコマンドの動作確認は
`--dry-run` を付けて手元で行ってください。

### 必要なもの

| ツール | インストール |
|--------|--------------|
| Swift 6.0+ | Xcode に同梱（`swift --version` で確認） |
| SwiftLint | `brew install swiftlint` |

### 任意: pre-commit フックで自動化する

毎回手で叩くのを忘れないよう、ローカルフックにしておくのを推奨します。

```bash
cat > .git/hooks/pre-commit <<'EOF'
#!/bin/sh
set -e
swift build
swiftlint lint --strict
EOF
chmod +x .git/hooks/pre-commit
```

---

# Contributing (English)

## About CI

This repository has no GitHub Actions CI jobs.

`Package.swift` declares `platforms: [.macOS(.v13)]` and the code depends on
Apple-only APIs and tools (`CryptoKit`, `xcodebuild`, `altool`), so building and
linting can only run on macOS. GitHub Actions macOS runners (`macos-15`) are
billed at a much higher rate than Linux runners, so CI has been removed in favor
of **running the checks locally**.

Please **always run the checks below before committing.**

## Pre-commit checks

```bash
# 1. Make sure it builds
swift build

# 2. Make sure it lints clean (warnings are errors)
swiftlint lint --strict
```

Both must pass before you commit or open a PR. A healthy run prints
`Build complete!` for `swift build` and `Found 0 violations, 0 serious` for
`swiftlint lint --strict`.

There are no automated tests in this project. To sanity-check the release
commands themselves, run them locally with `--dry-run`.

### Requirements

| Tool | Install |
|------|---------|
| Swift 6.0+ | Ships with Xcode (check with `swift --version`) |
| SwiftLint | `brew install swiftlint` |
