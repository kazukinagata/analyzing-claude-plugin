# analyzing-claude-plugin

Claude Code plugin 機構の挙動を **22 個の probe skill で実機検証**し、公式ドキュメントには書かれていない仕様や、ドキュメントと挙動が矛盾する箇所を洗い出したレポジトリ。

検証対象：
- **Claude Code CLI**: v2.1.143 → v2.1.146 → v2.1.150
- **Claude Desktop / Cowork**: v2.1.146-149（cloud VM 側）

## 何が分かるか

`docs/team-report.md` に **約 2,400 行の落とし穴まとめ**があります。主なトピック：

- **環境変数の伝播マトリクス**：`CLAUDE_PLUGIN_ROOT` / `CLAUDE_PLUGIN_DATA` / `CLAUDE_PROJECT_DIR` 等が plugin-level hook / skill frontmatter hook / Bash tool subprocess の 3 階層で非対称に渡される
- **`${VAR}` 事前置換の tier 別 allowlist**：skill body は最も広い、skill frontmatter は `${CLAUDE_PLUGIN_ROOT}` のみ
- **`sensitive: true` userConfig の挙動**：plugin-level hook には平文で env 渡し、skill body は Claude Code 本体が block 文字列に置換して leak 防止
- **slash 起動と自然言語起動で発火する hook が違う**：`PreToolUse:Skill` は自然言語のみ、`UserPromptExpansion` は slash のみ
- **OTel `claude_code.skill_activated` event** による 3 経路 (`user-slash` / `claude-proactive` / `nested-skill`) の追跡方法
- **Cowork 固有の罠**：host-adjacent VM + virtio-fs architecture、plugin-level PreToolUse block の無効化、validator が CLI より厳しい等

## 構成

```
verifier/                 # 22 probe skill を持つ検証用 plugin 本体
verifier-violator/        # validator block を意図的にトリガーする違反 plugin
docs/
  team-report.md          # 全 finding をまとめた本文（一番読むべき）
  check-matrix.md         # probe 別 verdict 表
  cowork-runbook.md       # Cowork 実機検証手順
  methodology.md          # 検証手法
scripts/                  # log 解析 / assert / Cowork zip 生成
findings/                 # 実行結果（per-version observations.md / report.md のみ git 管理）
MASTER-RUNBOOK.md         # 22 probe を順に回すための手動手順
LICENSE
```

## 検証方針

- **手動 runbook ベース**：`claude --print` 等の自動化は採用しない。人間が `claude` 対話セッションを起動し、`/verifier:NN-...` を順に叩く
- 自動化するのは log の集約・解析・判定（`scripts/assert.sh`）のみ
- グローバル `~/.claude/` を汚さないよう `CLAUDE_CONFIG_DIR=$(pwd)/findings/claude-home/` で project-local に閉じ込める
- 結果は `findings/v<version>/report.md` に verdict 6+1 種（PASS / FAIL / DOC-ALIGNED / PARTIAL / UNKNOWN / CANARY-FAILED / MANUAL-OK）で残す

## 再現手順

### 0. Pre-flight check

```sh
cd /path/to/analyzing-claude-plugin
. scripts/_env.sh
./scripts/capture-cli-help.sh
# findings/cli-help/*.log と STEP0-SUMMARY.md を生成
```

### 1. plugin install

```sh
. scripts/_env.sh
bash scripts/install-marketplace.sh
```

### 2. canary 確認

別 terminal で：

```sh
. scripts/_env.sh
claude
```

claude prompt 内で：

```
/verifier:00-canary
```

完了後に exit して：

```sh
./scripts/assert.sh 00
# PASS が返れば観測基盤 OK
```

### 3. 各 probe を MASTER-RUNBOOK 通りに

`MASTER-RUNBOOK.md` を順に追って 22 probe を回す。各 probe で `assert.sh NN` を叩いて verdict を確認。

最後に `./scripts/assert-all.sh` で `findings/v<version>/report.md` を生成。

### 4. Cowork 実機検証（任意）

```sh
./scripts/package-cowork.sh
```

で zip を作成、`docs/cowork-runbook.md` の手順で Claude Desktop にアップロード。

## 主要な発見ハイライト

| トピック | 観測 | 関連 § |
|---|---|---|
| `${VAR}` 事前置換 allowlist | tier ごとに別 allowlist で運用、skill frontmatter は `${CLAUDE_PLUGIN_ROOT}` のみ | team-report §1.2 |
| `sensitive: true` の skill body block | Claude Code 本体が `[sensitive option 'KEY' not available in skill content]` に置換して leak を防ぐ | team-report §1.4 |
| Cowork architecture | host-adjacent VM + virtio-fs。plugin-level hook は host 側、Bash tool は cloud VM 側 | team-report §2.0 |
| Cowork validator | CLI より厳しい：kebab-case 強制、description 内の `${...}`/`<...>` 拒否、UserPromptExpansion event 拒否 | team-report §2.16 |
| OTel `skill_activated` | `invocation_trigger=user-slash/claude-proactive/nested-skill` で 3 経路完全区別、Cowork でも emit | team-report Appendix B |

## ライセンス

MIT License — `LICENSE` 参照。
