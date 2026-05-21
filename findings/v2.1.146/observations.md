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

## probe 01-env-propagation （§1.1 / §3.1）

`./scripts/assert.sh 01` → **PASS (12/12 matched)**

### env 伝播 3 階層の実測表（v2.1.146 確定版）

| env | plugin-level hook | skill frontmatter hook | Bash tool subprocess | research §1.1 一致 |
|---|---|---|---|---|
| `CLAUDE_PLUGIN_ROOT` | ✅ 実値 | ✅ 実値 | ❌ unset | **PASS** |
| `CLAUDE_PLUGIN_DATA` | ✅ 実値 | ❌ (empty) | ❌ unset | **PASS** |
| `CLAUDE_PROJECT_DIR` | ✅ 実値 | ✅ 実値 | ❌ unset | **PARTIAL** — research §1.1 行 158 で「frontmatter は要追試」→ v2.1.146 で ✅ 確定 |
| `CLAUDE_PLUGIN_OPTION_*` | (userConfig 未設定で確認) | ❌ (empty) | ❌ unset | PASS（probe 04 で再確認） |
| `CLAUDE_SESSION_ID` | **❌ unset** | ❌ unset | ❌ unset | **FAIL** — research では plugin-level ✅ だったが v2.1.146 で退行。session_id は **hook の stdin JSON payload** にのみ存在 |
| `CLAUDE_SKILL_DIR` | ❌ unset | ❌ unset | ❌ unset | PASS（研究 §3.1 とおり env 経路では出ない） |
| `CLAUDE_CODE_ENTRYPOINT=cli` | ✅ | (推定 ✅) | ✅ | PASS |
| `CLAUDE_CODE_EXECPATH` | **❌ unset** | (未確認) | **✅ `/home/.../2.1.146`** | **FAIL / 非対称** — research では全層 ✅ だったが v2.1.146 では **plugin-level hook では unset、Bash subprocess では set** という逆転。CLAUDE_CODE_* の伝播は「メタ runtime 情報」として一括 ✅ という単純化が崩れた |
| **`CLAUDE_CODE_SESSION_ID`** | (未確認) | (未確認) | **✅ 実 UUID** | **NEW** — research に存在しなかった env。skill body から session id が取りたければ `CLAUDE_SESSION_ID` ではなく `CLAUDE_CODE_SESSION_ID` を使う |
| `CLAUDE_CODE_ENABLE_TELEMETRY` | — | — | ✅ `1` | NEW（テレメトリ on/off メタ） |
| `CLAUDE_EFFORT=xhigh` | — | — | ✅ | NEW（effort level 表示） |
| `CLAUDE_CONFIG_DIR` | (実装由来) | (実装由来) | ✅ user export 由来で届く | （元から user-controlled） |

### 含意

1. **plugin 作者が skill body から session 識別を欲しい場合は `$CLAUDE_CODE_SESSION_ID`** を使う。`$CLAUDE_SESSION_ID` env は v2.1.146 では全層 unset
2. **plugin-level hook で session_id を得るには `stdin` JSON payload の `session_id` フィールドを parse**（log.sh の stdin 取得ロジックが正しく動いている）
3. **CLAUDE_CODE_EXECPATH の plugin-level hook での unset** は研究と非対称な退行。これに依存する hook 設計（実行 claude バイナリ path を hook 内で取りたい等）は v2.1.146 では機能しない
4. **probe 09**（slash vs natural の 2 セッション分離）は research の `CLAUDE_SESSION_ID` env 前提で書いてあるが、v2.1.146 では `CLAUDE_CODE_SESSION_ID` または stdin JSON 経由で分離する必要あり — plan 改訂候補

### 根拠 log

- `findings/v2.1.146/no-sid/hooks.log` — `tag=session-start` および `tag=pretool-bash` セクション
- `findings/v2.1.146/no-sid/probe.log` — `[01-FM]` `[01-BODY]` 行
- 全 12 件の expected pattern が matched（`findings/expected/01-env-propagation.txt`）

### probe 01 後の追加検証（次 probe で確認予定）

probe 01 では `CLAUDE_CODE_SESSION_ID` が Bash tool subprocess に届くことを確認したが、plugin-level hook / skill frontmatter hook の env で見えるかは未検証だった（`log.sh` の dump 対象に含めていなかったため）。

→ `verifier/hooks/log.sh` の env dump リストに以下を追加：
- `CLAUDE_CODE_SESSION_ID`
- `CLAUDE_CODE_ENABLE_TELEMETRY`
- `CLAUDE_EFFORT`

次以降の probe で plugin-level hook の hooks.log にこれらの値が出るかを確認し、§1.1 表を完成させる。

### 研究 §1.1 改訂提案

```diff
- | `CLAUDE_PROJECT_DIR` | ✅ 設定（実測） | 本実験の probe では直接観測していない（要追試） | ❌ 未設定（実測） |
+ | `CLAUDE_PROJECT_DIR` | ✅ 設定（実測） | ✅ 設定（v2.1.146 実測） | ❌ 未設定（実測） |
- | `CLAUDE_CODE_ENTRYPOINT` / `CLAUDE_CODE_EXECPATH` 等 `CLAUDE_CODE_*` 系 | ✅ 設定 | ✅ 設定（推定） | ✅ **設定**（実測） |
+ | `CLAUDE_CODE_ENTRYPOINT` | ✅ 設定 | ✅ 設定（推定） | ✅ 設定 |
+ | `CLAUDE_CODE_EXECPATH` | ❌ unset（v2.1.146 で plugin-level から消失） | 未確認 | ✅ 設定（Bash subprocess には届く） |
+ | `CLAUDE_CODE_SESSION_ID`（新） | 未確認 | 未確認 | ✅ 実 UUID（v2.1.146 で確認） |
+ | `CLAUDE_SESSION_ID` | ❌ unset（v2.1.146 ; stdin JSON payload に格納） | ❌ unset | ❌ unset |
```

## 既知の v2.1.146 固有挙動（Claude Code バグ class）

- **skill body markdown pre-substitution で `$1` が空文字列に置換される** — `awk '{print $1}'` → `awk '{print }'` に化ける。研究 §1.7 の「skill body の `${VAR}` substitution」が `$1`（bash 数値変数）にも適用されるのが原因。回避策：env var 経由（`VERIFIER_VERSION_DIR` 等）か、`$1` を避けて `cut -d' ' -f1` を使う。本リポジトリは前者で全面修正済（commit `4b9e406`）

## probe 02-substitution-allowlist （§1.2 / §3.2）

`./scripts/assert.sh 02` → **PARTIAL (matched=6, missing=2, unwanted=0)**

### subclaim 単位の判定（v2.1.146 確定版）

| § subclaim | research v2.1.118-119 | v2.1.146 実測 | 判定 |
|---|---|---|---|
| skill body の `${CLAUDE_PLUGIN_ROOT}` | ✅ 置換 | `/home/.../verifier` | PASS |
| skill body の `${CLAUDE_PLUGIN_DATA}` | ✅ 置換 | `findings/.../plugins/data/verifier-verifier-mp` | PASS |
| skill body の `${CLAUDE_SKILL_DIR}` | ✅ 置換 (dirname) | `/home/.../skills/02-substitution-allowlist` | PASS |
| skill body の `${CLAUDE_SESSION_ID}` | ✅ 置換 (UUID) | `26316dd4-90e9-4c3d-85ab-1605bad62ee9` | PASS |
| skill body の `${CLAUDE_PROJECT_DIR}` | ❌ literal で残る | **✅ 置換される**（`/home/.../analyzing-claude-plugin`） | **FAIL** — research §1.2 の主張から仕様変更 |
| install 時の `${CLAUDE_PLUGIN_DATA}` validator block | ✅ block | **❌ block しない** | **FAIL** — research §1.2 / §3.2 行 187-191 の主張から退行 or 検査タイミング変更 |
| `claude plugin validate` 単体で `${CLAUDE_PLUGIN_DATA}` をエラー報告 | (研究で言及なし) | **❌ エラー無し**（author 警告のみ） | NEW — validator が `${CLAUDE_PLUGIN_DATA}` を skill frontmatter で検出しない |
| skill frontmatter の `${user_config.KEY}` → `/bin/sh: Bad substitution` | ✅ Bad substitution | ✅ `/bin/sh: 1: Bad substitution`（実測） | PASS |

### 02c 観察で同時確認した複数 subclaim

`02c-userconfig-in-frontmatter` を invoke 後に `echo hello world` を試したら：
```
PreToolUse:Bash hook error:
[echo "[02c violating] hello=${user_config.hello_message}"]:
/bin/sh: 1: Bad substitution
```

これで以下が同時に PASS 確定：

1. **§1.2 row 3**：skill frontmatter での `${user_config.KEY}` は ranatime 置換されず literal で `/bin/sh` に到達
2. **§1.3**：hook 実行 shell は `/bin/sh` (dash)。`${var.key}` の `.` を不正 parameter expansion として弾く
3. **§1.8**：skill frontmatter hook は **invoke 後** に登録される。02c invoke → 直後の Bash 呼び出しで PreToolUse:Bash が発火
4. **§2.4 / decision:block** に類似：PreToolUse hook が exit code 非ゼロを返すと tool 呼び出し全体が block される（02c のケースでは hook command が `/bin/sh` で失敗 → exit 非ゼロ → echo がブロック）

### 含意

- **`${CLAUDE_PROJECT_DIR}` 置換** は v2.1.146 で完全に効くようになった。研究時代に「project workspace を skill body から参照したい」用途で `${CLAUDE_PROJECT_DIR}` 経由 + Read tool を回避策にしていた箇所は、Bash tool での直接書き込みでも `${CLAUDE_PROJECT_DIR}` が使える（実測 SUBST_PROJECT_DIR=`/home/kazukinagata/projects/analyzing-claude-plugin`）
- **validator が install / validate コマンドで `${CLAUDE_PLUGIN_DATA}` を弾かなくなった** ことで、配布前の自動チェックではこの問題を検出できない。**実際のフックを実行してみるまで invalid な参照が露呈しない**ので、CI で `claude plugin validate` を回すだけでは不十分
- **plugin-level hook での `${user_config.KEY}` 置換**（research §1.2 row 3 の plugin-level 行）は本リポジトリで未検証。canary 回避のため hooks.json から削除した経緯あり。別 isolated probe を用意するか、observations 上は research の主張のまま「未確認」扱い

### 根拠 log

- `findings/v2.1.146/install.log` — 全体 23 行、validator エラーなし
- `findings/v2.1.146/no-sid/probe.log` 行 31-37（02-BODY セクション）
- 02c の Bad substitution は claude session output のみ（hook stderr は context に流れたが log file には残らない）— observation は本ファイルが一次記録

### 研究 §1.2 改訂提案

```diff
- | `${CLAUDE_PROJECT_DIR}` | ✅ | 未検証 | ❌ literal のまま残る |
+ | `${CLAUDE_PROJECT_DIR}` | ✅ | 未検証 | ✅ 置換される（v2.1.146 で挙動変更）|
```

```diff
- 観測した validator エラー（v2.1.118、skill frontmatter hook で `${CLAUDE_PLUGIN_DATA}` を参照した場合）：
- Hook command references ${CLAUDE_PLUGIN_DATA} but only ${CLAUDE_PLUGIN_ROOT}
- is available for skill hooks (${CLAUDE_PLUGIN_DATA} is plugin-only).
+ 観測した validator エラー（v2.1.118）：上記の文言。
+ v2.1.146 では install / `claude plugin validate` どちらも block せず install 成功。
+ 実際のフック実行時に shell エラー（/bin/sh: Bad substitution 等）として顕在化する形に変わった。
```

---

(以降、probe 03-21 を回しながら追記)
