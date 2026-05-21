# Observations — Claude Code v2.1.146

実行日：2026-05-21
比較対象：`sandbox/research.md` (Claude Code v2.1.118-119, 2026-04 観測)

各 probe を回しながら、研究の主張と現バージョン実測の差分を蓄積する。最終的に `findings/v2.1.146/report.md` の verdict と組み合わせて research-summary.md の改訂材料にする。

書式：
```
## probe NN / research §X.Y
- **research の主張**: ...
- **v2.1.146 実測**: ...
- **判定**: PASS / FAIL / DOC-ALIGNED / PARTIAL
- **根拠 log**: `findings/v2.1.146/<sid>/hooks.log:行` 等
```

---

## Step 0 / 環境 baseline

- Claude Code: **v2.1.146**（research v2.1.118-119 から 28 バージョン進んだ）
- /bin/sh = dash（変化なし）
- `$BASH_VERSION` 空、`$RANDOM` 空、`date +%N` 動作（dash 想定通り）
- `--permission-mode` 選択肢: acceptEdits, auto, bypassPermissions, default, dontAsk, plan（変化なし）
- 新 flag 発見: `--bare`（hook / LSP / plugin sync 等をスキップする mode、CLAUDE_CODE_SIMPLE=1 を set）
- 新 flag 発見: `--plugin-url`（URL から zip fetch、`--plugin-dir` の URL 版）
- 既存：`--settings-mode` / `--command` は v2.1.143 で存在しないことを確認（plan の "A 経路" は破棄済）
- `claude plugin install` は marketplace 経由のみ（CLI で path 直接 install 不可、確認済）

## Step 0 副作用：CLAUDE_CONFIG_DIR 隔離の限界

`CLAUDE_CONFIG_DIR=findings/claude-home/` を export しても、以下は隔離されない or 共有が必要：
- `~/.claude.json`（host）と `findings/claude-home/.claude.json` は別ファイル → 隔離 home で初回起動扱いになり welcome flow が走る → `.claude.json` を host に symlink して回避（`scripts/_env.sh`）
- `~/.claude/.credentials.json` も隔離 home に無い → host に symlink で auth 共有
- `~/.claude/paste-cache/`, `~/.claude/shell-snapshots/`, `~/.claude/history.jsonl`, `~/.claude/sessions/` は新 claude セッション起動時に書き込まれる（隔離対象外）

縮退目標「`~/.claude/plugins/` と `~/.claude/settings.json` の `pluginConfigs` を汚さない」は達成。

## probe 00-canary （観測基盤）

`./scripts/assert.sh 00` → **PASS** (8/8 matched)。観測基盤健全。

詳細 log: `findings/v2.1.146/no-sid/{hooks.log, probe.log}` (CLAUDE_SESSION_ID env が unset なので sid=no-sid)。

## probe 01-env-propagation の暫定観察（00-canary log から先取り）

probe 01 を本格走らせる前に、canary log から判明した env 伝播（plugin-level hook）：

| env | research §1.1 主張 | v2.1.146 実測 | 判定 |
|---|---|---|---|
| `CLAUDE_PLUGIN_ROOT` | ✅ set | ✅ set（`/home/.../verifier`） | PASS |
| `CLAUDE_PLUGIN_DATA` | ✅ set | ✅ set（`findings/claude-home/plugins/data/verifier-inline`） | PASS |
| `CLAUDE_PROJECT_DIR` | ✅ set | ✅ set | PASS |
| `CLAUDE_CODE_REMOTE` | 空 | (unset) | PASS（"unset" と "空" は同義に扱う） |
| **`CLAUDE_SESSION_ID`** | ✅ set（未確認だった） | **❌ unset**（env としては取れない）。stdin の JSON payload に `session_id` フィールドがあり、本物の UUID はそこに入っている | **FAIL / 仕様改訂** |
| **`CLAUDE_CODE_EXECPATH`** | ✅ set | **❌ unset** | **FAIL / 退行 or 仕様改訂** |
| `CLAUDE_CODE_ENTRYPOINT=cli` | ✅ set | ✅ set | PASS |
| `CLAUDE_PLUGIN_OPTION_*` | ✅ userConfig 設定時 | （未設定で確認） | PENDING (probe 04 で確定) |

**含意**：plugin 作者が session 識別を欲しい場合、`$CLAUDE_SESSION_ID` env ではなく hook の **stdin JSON** から `session_id` を parse する必要がある。研究 §1.1 の表で `CLAUDE_SESSION_ID` を「(未確認)」にしていた行は v2.1.146 で「env として export されない」に確定。

なお log.sh は CLAUDE_SESSION_ID env が unset の場合 `sid=no-sid` にフォールバックする実装になっており、現バージョンでは全 log が `no-sid/` 配下に集約される。**probe 09**（slash vs natural の 2 セッション分離）は CLAUDE_SESSION_ID env に依存していたので、stdin payload から sid を抽出するか、`fork-session` 等の別経路で対処が必要 — 後で plan 改訂候補。

## 既知の v2.1.146 固有挙動（Claude Code バグ class）

- **skill body markdown pre-substitution で `$1` が空文字列に置換される** — `awk '{print $1}'` → `awk '{print }'` に化ける。研究 §1.7 の「skill body の `${VAR}` substitution」が `$1`（bash 数値変数）にも適用されるのが原因。回避策：env var 経由（`VERIFIER_VERSION_DIR` 等）か、`$1` を避けて `cut -d' ' -f1` を使う。本リポジトリは前者で全面修正済（commit `4b9e406`）

---

(以降、probe 01-21 を回しながら追記)
