# RUNBOOK: 01-env-propagation

## 検証内容（§1.1 / §3.1）

env 伝播が 3 階層で非対称：

| 環境変数 | plugin-level hook | skill frontmatter hook | Bash tool subprocess |
|---|---|---|---|
| `CLAUDE_PLUGIN_ROOT` | ✅ | ✅ | ❌ |
| `CLAUDE_PLUGIN_DATA` | ✅ | ❌ | ❌ |
| `CLAUDE_PROJECT_DIR` | ✅ | (未確認) | ❌ |
| `CLAUDE_PLUGIN_OPTION_*` | ✅ | ❌ | ❌ |
| `CLAUDE_CODE_*` (entrypoint, execpath) | ✅ | ✅ | ✅ |

## 事前準備

- 00-canary が PASS していること

## 手順

```sh
cd /home/kazukinagata/projects/analyzing-claude-plugin
. scripts/_env.sh
claude --plugin-dir ./verifier
```

最初のプロンプトで：
```
/verifier:01-env-propagation
```

Claude が step 1 → step 2 を順に実行することを承認。exit して `./scripts/assert.sh 01`。

## subclaim

1. **plugin-level hook**: `hooks.log` の `tag=session-start` セクションに `CLAUDE_PLUGIN_DATA=[<実値>]` が出る
2. **skill frontmatter hook**: `probe.log` の `tag=fm-registered` 行で `DATA=[(empty)]`、`OPT_HELLO=[(empty)]`
3. **Bash tool subprocess**: `probe.log` の `[01-BODY] CLAUDE_PLUGIN_ROOT=[(unset)]` のように plugin scope の env が unset
4. `CLAUDE_CODE_*` 系は全 3 層に届く

## 想定 verdict

- 全 subclaim 一致 → **PASS**
- frontmatter で DATA が見える / Bash subprocess で PLUGIN_ROOT が見える → **FAIL（finding 変化）**
- alive-check 不在 → **UNKNOWN**
