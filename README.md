# analyzing-claude-plugin

Claude Code プラグイン機構の挙動を **現バージョンで再検証する** ための probe プラグインと runbook。

source となる調査記録（`/home/kazukinagata/projects/sandbox/research.md` / `research-summary.md`）は Claude Code **v2.1.118-119** / Claude Desktop **1.3883.0** で 2026-04 に取られたもの。現在は **Claude Code v2.1.143** + 最新 Claude Desktop。25 バージョン進んでいるため、どの finding がまだ生きていてどれが崩れているかを確認する。

## ゴール

- research.md の全 finding（§1.1〜§2.13）を 22 個の probe skill でカバー
- **手動 runbook ベース**：人間が `claude` 対話セッションを起動し、`MASTER-RUNBOOK.md` に沿って probe を順に叩く。Claude を `--print` で勝手に動かす自動化は採用しない
- 自動化するのは log の集約・解析・判定（`scripts/assert.sh`）のみ
- 結果は `findings/v2.1.143/report.md` に verdict 6+1 種（PASS / FAIL / DOC-ALIGNED / PARTIAL / UNKNOWN / CANARY-FAILED / MANUAL-OK）で残す

## グローバル環境を汚さない方針

すべての script は `CLAUDE_CONFIG_DIR=$(pwd)/findings/claude-home/` を export して claude コマンドを呼ぶ。これでプラグイン install 先、settings.json、installed_plugins.json などが project-local に閉じる。

**完全隔離は保証されない**：以下は CLAUDE_CONFIG_DIR の制御外で `~/.claude/` に書かれる可能性がある：
- `~/.claude/.credentials.json`（OS keychain fallback）
- `~/.claude/projects/<hash>/`（session 履歴）
- `~/.claude/file-history/`
- OS keychain（macOS Keychain / Linux secret service）

縮退目標：「`~/.claude/plugins/` 配下と `~/.claude/settings.json` の `pluginConfigs` セクションを汚さない」。

## 使い方

### 1. Pre-flight check (step 0)

最初に必ず：

```sh
./scripts/capture-cli-help.sh
# findings/cli-help/*.log と STEP0-SUMMARY.md を生成
```

これで v2.1.143 の `claude plugin --help` 系の構文・schema 互換性・shell 実体を確認する。

### 2. canary 確認

観測基盤が生きていることを確認：

```sh
# 別 terminal で：
. scripts/_env.sh
claude --plugin-dir ./verifier
# プロンプトで：
/verifier:00-canary
# 完了したら exit
./scripts/assert.sh 00
# PASS が返れば OK。FAIL/CANARY-FAILED なら後続 probe は走らせる意味なし
```

### 3. 各 probe を MASTER-RUNBOOK 通りに

`MASTER-RUNBOOK.md` を上から下に追って 22 probe を回す。各 probe で `assert.sh NN` を叩いて verdict を確認。

最後に `./scripts/assert-all.sh` で `findings/v2.1.143/report.md` を生成。

### 4. Cowork 実機検証（任意）

`./scripts/package-cowork.sh` で zip を作成、`docs/cowork-runbook.md` の手順で Claude Desktop にアップロード。

## ディレクトリ構成

```
verifier/                 # 検証用プラグイン
verifier-violator/        # 02 / 20 用 validator block 試行プラグイン（install 失敗を観察）
scripts/                  # 自動化はここに（log 解析・sandbox セットアップ）
docs/                     # check-matrix / cowork-runbook / methodology
findings/                 # 実行結果（gitignore 対象）
  claude-home/            # CLAUDE_CONFIG_DIR が指す project-local home
  cli-help/               # step 0 の出力
  expected/               # 各 probe の expected 文字列
  v2.1.143/               # バージョン別の結果
MASTER-RUNBOOK.md         # 22 probe 分の手動手順
```

## 参考資料

- `/home/kazukinagata/projects/sandbox/research.md` — source の調査記録（read-only）
- `/home/kazukinagata/projects/sandbox/research-summary.md` — 高密度マッピング
- `/home/kazukinagata/.claude/plans/greedy-snacking-cook.md` — このリポジトリの設計プラン
