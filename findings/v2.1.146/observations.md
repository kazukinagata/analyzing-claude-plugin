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

1. **§1.2 row 3**：skill frontmatter での `${user_config.KEY}` は **userConfig の設定状態と無関係に** runtime 置換されず、literal で `/bin/sh` に到達。Claude Code は plugin-level hook では `${user_config.KEY}` を置換するが、skill frontmatter hook では一切置換しない仕様（plugin-only な置換）。今回の観察時 userConfig は未設定（`CLAUDE_PLUGIN_OPTION_HELLO_MESSAGE=[(unset)]` を hooks.log で確認）だが、設定済でも結果は同じになる
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

## probe 03-shell-binsh （§1.3）

`./scripts/assert.sh 03` → **PASS (7/7 matched)**（expected の format ミスマッチ修正後）

### subclaim 単位の判定

| § subclaim | research v2.1.118-119 | v2.1.146 実測 | 判定 |
|---|---|---|---|
| hook 実行 shell は `/bin/sh` | ✅ dash 想定 | ✅ `/usr/bin/dash` （`readlink -f /bin/sh`） | PASS |
| `/bin/sh -c` で `BASH_VERSION` 空 | ✅ | ✅ `BASH_VERSION=[]` | PASS |
| `/bin/sh -c` で `$RANDOM` 空 | ✅（dash 非対応） | ✅ `RANDOM=[]` | PASS |
| `[[ ]]` 構文で syntax error | ✅ | ✅ `/bin/sh: 1: [[: not found` | PASS |
| `${PWD^^}` で Bad substitution | ✅ | ✅ `/bin/sh: 1: Bad substitution` | PASS |
| frontmatter hook 内の bashism がエラー | （明示的観察なし） | ✅ `[03-FM-bashisms ...]` の printf 自体が ${PWD^^} の expansion 失敗で実行されず、代わりに `/bin/sh: 1: Bad substitution` だけが log に流れる（hook stderr の 2>&1 redirect 経由） | NEW (bonus 観察) |

### probe 03 で学んだメタな設計教訓

**frontmatter hook で意図的に失敗するコマンドを書くと PreToolUse:Bash の exit 非ゼロが伝播し Bash tool 全体が block される**：

- 初回試行ではこの問題で skill body が一切走らなかった
- 修正：`command: '... ; exit 0'` を追加して hook が常に 0 で終わるようにする
- 同じパターンで失敗するコマンドを置く probe（02c 含む将来の probe）は同じ`; exit 0` イディオムを使う必要あり

### Claude plugin update / cache の挙動（probe 06 の前哨観察）

probe 03 を修正する過程で判明：

1. **`claude plugin update verifier@verifier-mp -s local` は version 番号で判定** — plugin.json の version を bump しない限り「already at latest version」と返って cache を更新しない。content hash や git commit sha は見ない
2. **`installed_plugins.json` には `installPath` が cache を指している**にもかかわらず、probe 02 では `CLAUDE_PLUGIN_ROOT` が source path を返した → runtime は source 読み（or 両方読む）。**probe 06 で確定する**
3. 開発ループでは **uninstall + reinstall が cache 強制更新の手段** — verifier の SKILL.md 修正後 `claude plugin uninstall ... -y && claude plugin install ...` で cache が再生成

### 根拠 log

- `findings/v2.1.146/no-sid/probe.log` 行末から逆順 ~15 行（`[03-BODY]` および `/bin/sh: 1: Bad substitution`）

### 研究 §1.3 改訂提案

```diff
- hook の `command` は **`/bin/sh` で実行される**（bash ではない）。
- **根拠**：`${user_config.hello_message}` を skill frontmatter hook に書いた際のエラーメッセージ：
- /bin/sh: 1: Bad substitution
+ hook の `command` は **`/bin/sh` で実行される**（bash ではない）。v2.1.146 (WSL Ubuntu) では `/bin/sh -> /usr/bin/dash`。
+ **根拠**：`${PWD^^}`（bash 固有 uppercase 修飾）や `[[ ]]` を hook command に書くと
+ `/bin/sh: 1: Bad substitution` / `/bin/sh: 1: [[: not found` が出る（probe 03 で実測）。
+ また、frontmatter hook の command が `; exit 0` を付けずに失敗すると、PreToolUse:Bash の
+ exit 非ゼロが Bash tool 全体を block するため、意図的失敗コマンドは exit 0 を強制する idiom が必要。
```

## probe 04-sensitive-leak （§1.4）

`./scripts/assert.sh 04` → **PASS (5/5 matched)**

### subclaim 単位の判定

| § subclaim | research v2.1.118-119 | v2.1.146 実測 | 判定 |
|---|---|---|---|
| 非機密値が `CLAUDE_PLUGIN_OPTION_<KEY>` env に届く（plugin-level hook） | ✅ | ✅ `CLAUDE_PLUGIN_OPTION_HELLO_MESSAGE=[hello-from-cli-CANARY]` | PASS |
| **sensitive: true 値も平文で env 露出**（plugin-level hook） | ✅（仕様、コメントで明示） | ✅ `CLAUDE_PLUGIN_OPTION_API_SECRET=[secret-xyz-CANARY]` | PASS |
| OPTION_* env は Bash tool subprocess に届かない（§1.1 関連） | ✅ | ✅ `[04-BODY] CLAUDE_PLUGIN_OPTION_API_SECRET=[(unset)]` | PASS |
| sensitive 値の保存場所が非機密と分離されている | ✅ keychain or `.credentials.json` フォールバック（§4.1 / §4.2 に明記） | ✅ WSL Ubuntu では `.credentials.json` フォールバック側に格納（`pluginSecrets.<id>.<key>`） | PASS — WSL は keychain 非対応のためフォールバック路を観察したのみ、仕様変更ではない |
| 非機密値は `pluginConfigs.<id>.options.<key>` 平文 | ✅ settings.json | ✅ `settings.json.pluginConfigs.verifier@verifier-mp.options.hello_message=hello-from-cli-CANARY` | PASS |

### v2.1.146 で判明した pluginConfigs スキーマ詳細

実測で確定した正しい入れ子（research には言及無し or 不正確）：

```json
{
  "pluginConfigs": {
    "<plugin>@<marketplace>": {
      "options": {
        "<key>": "<value>"
      }
    }
  }
}
```

**注意：`options` という入れ子が必須**。`pluginConfigs.<id>.<key>` 直下に書いてもランタイムは拾わない（私が当初試した形式で `(unset)` のままだった）。

sensitive 値の格納場所：

```json
// .credentials.json
{
  "claudeAiOauth": {...},
  "mcpOAuth": {...},
  "pluginSecrets": {
    "<plugin>@<marketplace>": {
      "<sensitive_key>": "<value-plain-text>"
    }
  }
}
```

### `/plugins` UI 経由の設定が正規ルート

probe 04 の試行錯誤で判明したフロー：

1. 直接 `settings.json` を編集して `pluginConfigs.<id>.<key>` 形式で書いても拾われない
2. **`/plugins` UI を起動**して該当 plugin の Configure options から値を入力すると、正しい schema（`options.<key>` 入れ子）で書き込まれる
3. sensitive: true マーク付きの値は `.credentials.json` の `pluginSecrets` に行く
4. ランタイムでは両方とも `CLAUDE_PLUGIN_OPTION_<KEY>` env として plugin-level hook に届く（保存先による差は無い）

### 含意

- **CI で plugin 配布前にユーザに値入力させたい場合、`/plugins` UI 起動を runbook に明記**する必要がある（settings.json の direct edit は schema を間違えると silently 動かない）
- **`sensitive: true` の実保護レベルは「平文 file への保存先分離」のみ**。keychain（OS の secure storage）ではなく `.credentials.json` 内の別セクションに行く。ファイルに `0600` の permission は付くが、OS secret service ではない
- **plugin 作者が「実際に effective な userConfig 値」を確認するには hooks.log の env dump が必要** — settings.json だけ見ても sensitive 値は見えない

### 副次的な観察：CLAUDE_CONFIG_DIR symlink の副作用

本リポジトリは `findings/claude-home/.credentials.json` を `~/.claude/.credentials.json` への symlink にしている（auth 共有のため）。**`/plugins` UI で書き込んだ `pluginSecrets` は symlink 越しにホストの `~/.claude/.credentials.json` に書かれた**。検証目的の CANARY 値なので問題ないが、本物の API key を試すなら symlink を一旦切るべき。

### 根拠 log

- `findings/v2.1.146/no-sid/hooks.log` — `tag=user-prompt-submit` 以降の env section
- `findings/claude-home/settings.json` — pluginConfigs section
- `findings/claude-home/.credentials.json`（symlink）→ ホスト `~/.claude/.credentials.json` の pluginSecrets セクション

### 研究 §1.4 / §4.2 への補足提案

研究 §4.1 と §4.2 でプラットフォーム別の格納先は既に書かれている（「OS キーチェーン or `~/.claude/.credentials.json`（WSL など OS キーチェーン非対応環境）」）。v2.1.146 / WSL Ubuntu の実測はそのフォールバック路の具体構造を確定したのみ：

```diff
+ WSL Ubuntu / v2.1.146 実測：機密値は `.credentials.json` の以下の構造に格納される
+   {
+     "pluginSecrets": {
+       "<plugin>@<marketplace>": {
+         "<sensitive_key>": "<value-plain-text>"
+       }
+     }
+   }
```

```diff
- `/plugins` UI / Configure options から値を入力 → settings.json に書き込まれる
+ `/plugins` UI / Configure options から値を入力 →
+ 非機密：settings.json の `pluginConfigs.<id>.options.<key>` 入れ子に書き込まれる
+ 機密：keychain（OS 対応時）or `.credentials.json.pluginSecrets.<id>.<key>`（WSL 等のフォールバック）に書き込まれる
+ settings.json を direct edit する場合は `.options` 入れ子を忘れると runtime が拾わない
```

## probe 05-userconfig-trigger （§1.5）

`./scripts/assert.sh 05` → **PARTIAL (matched=1, missing=1)** （automation 上は 1 件のみ自動判定。残りは手動観察）

### route 単位の判定

| § route | research v2.1.118-119 | v2.1.146 実測 | 判定 |
|---|---|---|---|
| route 1: `claude plugin install` / `enable`（CLI shell） | silent（no prompt） | silent（`install-marketplace.sh` 実行で prompt 無し、両 plugin install 成功） | PASS |
| route 2: `/plugins` UI → Configure options 手動入力 | 入力フォーム表示 | 入力フォーム表示（probe 04 で実際に値入力済）。`Hello message` / `Mock API secret` の 2 項目 + `Save configuration` ボタン | PASS |
| route 3: `/plugins` で disable → enable（参照あり + 未設定なら prompt） | 条件付き prompt | **silent 観察**（現状：参照無し + 値設定済の組み合わせ） → 「prompt 不要」のケースなので silent は研究と整合 | PASS（条件付き — fully test には参照あり + 値 unset の状態が必要） |
| route 4: 参照あり + 値未設定で hook が走った場合 → `Plugin option "X" isn't set.` エラー | hook error | **未直接観察**：現在 hooks.json に `${user_config.*}` の plugin-level 参照無し（canary 安定化のため削除済、blocker #1 fix の経緯）。02c-userconfig-in-frontmatter は frontmatter 参照なので `Bad substitution`（research §1.2）になり別 error class | DEFERRED — verifier に plugin-level reference を一時追加する隔離 probe が必要 |

### /plugins UI の v2.1.146 挙動

- **タブ構成**：`Discover` / `Installed` / `Marketplaces` / `Errors`（Tab キーで移動）
- **Installed** タブで verifier@verifier-mp の Local section にカーソル移動 → Enter で詳細
- 詳細画面の action：`Disable plugin` / `Add to favorites` / `Mark for update` / `Configure options` / `Update now` / `Uninstall` / `Back to plugin list`
- `Configure options` を選ぶと userConfig フィールドが list 表示される。非機密値は平文表示、sensitive 値は `(unchanged)` のように mask 表示
- enable 操作後は `Run /reload-plugins to apply.` のヒントが表示される（v2.1.146 で `/reload-plugins` を打つ必要あり）

### Configure options UI で観察された詳細

```
Configure verifier
Plugin options
  ❯ Hello message    hello-from-cli-CANARY      <- 非機密、現在値が平文表示
    Mock API secret  (unchanged)                <- 機密、masked
    Save configuration
Non-sensitive probe value (stored in settings.json)
```

description のヘルプテキスト（"Non-sensitive probe value..."）も画面下部に表示される。

### disable → enable 観察

```
✓ Enabled verifier. Run /reload-plugins to apply.
```

prompt は出ず。**ただしこれは「参照無し + 値設定済」の組み合わせなので、研究 §1.5 row 3 の「参照あり + 値未設定」分岐を test できているわけではない**。

### 副次的な観察

- `/plugins` Installed タブには **ホスト `~/.claude.json` 由来の MCP servers**（Notion, Slack, Atlassian Rovo, Google Calendar, Gmail, Google Drive 等）も表示された。`CLAUDE_CONFIG_DIR` を `findings/claude-home` に redirect しても `.claude.json` の symlink でホスト側 MCP state が共有されているため。検証用途では問題なし（ノイズだけ）

### 残課題（probe 05 完全カバーには）

route 4 を auto-test するには：

1. `verifier-violator/hooks/hooks.json` に plugin-level `SessionStart` で `echo "${user_config.X}"` 参照を仕込む（X は値未設定の任意キー）
2. その violator を install
3. session 起動 → `Plugin option "X" isn't set.` エラーが出るか観察

または現在の `verifier-violator/skills/02c-userconfig-in-frontmatter/SKILL.md` を plugin-level hook 版に作り直す。

これは observations.md に「**route 4 deferred — verifier-violator-userconfig-pluginlevel という第 5 の独立 plugin variant が必要**」として記録。次の検証 round で対応するか、現実装で「research §1.5 row 4 は手動 setup が必要」を許容するかは判断保留。

### 研究 §1.5 改訂提案

```diff
  | 操作 | prompt 表示 |
  |---|---|
- | `claude plugin install` / `enable`（CLI シェル） | ❌ silent |
+ | `claude plugin install` / `enable`（CLI シェル） | ❌ silent（v2.1.146 / WSL Ubuntu 実測 PASS） |
- | `/plugins` UI → Configure options（手動） | ✅ 入力フォーム |
+ | `/plugins` UI → Configure options（手動） | ✅ 入力フォーム（v2.1.146 では `Installed → ❯ verifier → Configure options` の階層） |
  | `/plugins` UI → disable → enable | プラグインのどこかで `${user_config.KEY}` が参照されており、かつ値が未設定の場合のみ ✅ |
- | 参照されていて値未設定で hook が走った場合 | hook error（`Plugin option "X" isn't set.`） |
+ | 参照されていて値未設定で hook が走った場合 | hook error（`Plugin option "X" isn't set.`） — v2.1.146 では未直接観察、verifier 本体から user_config 参照を canary 安定化のため削除済、隔離 probe で再検証する必要あり |
+
+ v2.1.146 で確認できなかった条件：route 3/4 の「参照あり + 値未設定」分岐。参照を持つ別 plugin variant を作って再観察すべき。
```

## probe 06-marketplace-cache （§1.6）

`./scripts/assert.sh 06` → **PASS (2/2 matched)**（ただし比較ロジックに難あり、結論は他の証拠と合わせて正しい）

### subclaim 単位の判定

| § subclaim | research v2.1.118-119 主張 | v2.1.146 実測 | 判定 |
|---|---|---|---|
| docs：cache copies are used at runtime | (docs 記述) | — | reference |
| **observation**：cache はコピー作成されるが runtime は **source path** を使う | ✅ source 使用 | ✅ probe 02 の SUBST_ROOT = `/home/.../verifier`（source）, cache_dir = `findings/.../cache/verifier-mp/verifier/0.1.0`（別 path） | PASS — finding 維持、docs との矛盾は v2.1.146 でも継続 |
| `installed_plugins.json.installPath` は cache を指す | （研究で明示せず） | ✅ `installPath: findings/.../cache/verifier-mp/verifier/0.1.0`（実測） | NEW supporting evidence — metadata と runtime path の不整合 |

### v2.1.146 実測

`findings/claude-home/plugins/cache/verifier-mp/` 配下に各 plugin 0.1.0 dir が作られ、source の copy が置かれている：
- `verifier/0.1.0/.claude-plugin/plugin.json`
- `verifier-violator/0.1.0/.claude-plugin/plugin.json`

しかし runtime の `${CLAUDE_PLUGIN_ROOT}` は source path (`verifier/` 直下) を返す。これは：
- probe 02 SUBST_ROOT = `/home/kazukinagata/projects/analyzing-claude-plugin/verifier` で confirmed
- log.sh の env dump でも `CLAUDE_PLUGIN_ROOT=/home/.../verifier` (source) と表示

### probe 03 で観察した cache 更新の挙動と組み合わせて

- `claude plugin update` は version 比較のみで content hash や git SHA を見ない（probe 03 で記録）
- そのため source 側を編集しても `plugin update` では cache が再生成されない
- `claude plugin uninstall ... && install ...` で cache 強制再生成
- ただし **runtime が source 読みなので、cache の stale 状態自体は実害がない**（probe 03 で SKILL.md 修正後すぐ反映できたのもこのため）

→ 「cache は実質 dead data」。`installed_plugins.json.installPath` が cache を指すのは misleading なメタデータ。

### probe 06 SKILL の自己批判

`verifier/skills/06-marketplace-cache/SKILL.md` の比較ロジック：

```bash
[ "$CLAUDE_PLUGIN_ROOT" = "$cache_dir" ]
```

これは Bash tool subprocess 内で実行されるため `$CLAUDE_PLUGIN_ROOT` は **常に unset = 空文字列**（§1.1）。cache_dir と空文字列の比較で「異なる」となり常に VERDICT=PASS を出すバグ。

ただし**結論は他の証拠（probe 02 の SUBST_ROOT）と整合**しているので、§1.6 自体の verdict は PASS で妥当。SKILL を直接 patch するなら：

```bash
# 比較するべき正しい値は ${CLAUDE_PLUGIN_ROOT} の **substituted** 形
ROOT='${CLAUDE_PLUGIN_ROOT}'    # Claude Code が pre-substitute するので実行時には source path
# ... cache_dir も plugin.json の dirname の親（.claude-plugin の親）に修正
```

これは次の verification round で適切に修正候補。今回は「結論 PASS、SKILL 設計の改善は deferred」として記録。

### 含意

- **plugin 作者が `CLAUDE_PLUGIN_ROOT` に従って source を参照する設計**は v2.1.146 でも有効（cache copy への参照ではない）
- ローカル marketplace 開発時の iteration loop は source 編集 → 即反映（cache 更新不要、ただし `/reload-plugins` は必要）
- **配布される plugin の整合性**：marketplace install の cache を信用するな（runtime とは別物）。ユーザに見える state は source ベース

### 研究 §1.6 改訂提案

```diff
- docs は「copies marketplace plugins to the user's local plugin cache (`~/.claude/plugins/cache`) rather than using them in-place」と書くが、**ローカル directory marketplace では `CLAUDE_PLUGIN_ROOT` が source パスを指す**。cache はコピーされるが hook 実行には使われない。
+ docs は「copies marketplace plugins to the user's local plugin cache (`~/.claude/plugins/cache`) rather than using them in-place」と書くが、**ローカル directory marketplace では `CLAUDE_PLUGIN_ROOT` が source パスを指す**（v2.1.118-119 / v2.1.146 共通）。
+ cache はコピーされるが hook 実行には使われない。
+ v2.1.146 で確認：`installed_plugins.json` の `installPath` 自体は cache を指す形で記録されるため metadata と runtime path の不整合がある。`claude plugin update` は version 比較のみで content hash を見ないので、開発中の SKILL.md 編集を反映させるには `claude plugin uninstall ... -y && claude plugin install ...` で cache を強制再生成する必要がある（ただし runtime は source 読みなので大半のケースで cache 状態は無視可能）。
```

## probe 07-skill-body-subst （§1.7）

`./scripts/assert.sh 07` → **PASS (3/3 matched)**

### subclaim 単位の判定

| § subclaim | research v2.1.118-119 | v2.1.146 実測 | 判定 |
|---|---|---|---|
| **Read tool 経由で SKILL.md を読むと `${VAR}` は literal で残る** | ✅ literal | ✅ literal — 下記 Step A の verbatim | PASS |
| **`/verifier:07-...` で invoke すると `${CLAUDE_PLUGIN_ROOT}` が絶対 path に substituted** | ✅ substituted | ✅ `/home/kazukinagata/projects/analyzing-claude-plugin/verifier` | PASS |
| substituted は **invoke 経路の context load 時点** に発生 | ✅（推定） | ✅ 下記 Claude の発言「skill body reached me with substitution already applied」と整合 | PASS |

### Step A — Read 経路（verbatim 引用）

claude にプロンプトで「`verifier/skills/07-skill-body-subst/SKILL.md` ファイルを Read tool で読んで、その中で `"CHECK_LINE:"` で始まる行を**そのまま**コピーして見せてください」と依頼。

Claude の返答：

```
CHECK_LINE: PLUGIN_ROOT_VALUE=${CLAUDE_PLUGIN_ROOT}
```

`${CLAUDE_PLUGIN_ROOT}` は展開されずリテラルで返ってきた。

### Step B — Invoke 経路

`/verifier:07-skill-body-subst` を実行。probe.log に出た行：

```
[07-BODY] INVOKE_LINE: PLUGIN_ROOT_VALUE=/home/kazukinagata/projects/analyzing-claude-plugin/verifier
```

substituted（probe 02 SUBST_ROOT と同じ source path）。

### Claude 自身の観察

Step B で Claude が補足した発言：

> The CHECK_LINE shows PLUGIN_ROOT_VALUE=/home/kazukinagata/projects/analyzing-claude-plugin/verifier — i.e., `${CLAUDE_PLUGIN_ROOT}` was already substituted to the literal path **before the skill body reached me**.

これは Claude Code が **invoke 経路で context load 直前** に substitute する設計と整合（research §1.7 / §3.2 のバイナリ調査結果と一致）。

### 含意

- **`${CLAUDE_PLUGIN_ROOT}` の表記を SKILL body に書くと、ユーザが Read tool で skill ファイルを覗いた時に literal、invoke で起動した時に絶対 path、という二重の見え方**になる。documentation 用途で path を見せたい場合は両方の挙動を念頭に書くべき
- plugin 作者の debug：ユーザに「skill 起動して、`${CLAUDE_PLUGIN_ROOT}` の値を echo して」と頼めば実 path を取れる（Read 依頼だと literal）
- v2.1.146 でも research §1.7 のバイナリ実装（`R.replace(/\$\{CLAUDE_SKILL_DIR\}/g, ...)` 等）が機能している

### 研究 §1.7 改訂提案

```diff
- skill body markdown の `${CLAUDE_PLUGIN_ROOT}` 等は **skill が invoke されて context に load される時点**でランタイムが substitute する。**Read/Grep tool で SKILL.md をファイルとして読む経路では literal のまま**。
+ skill body markdown の `${CLAUDE_PLUGIN_ROOT}` 等は **skill が invoke されて context に load される時点**でランタイムが substitute する。**Read/Grep tool で SKILL.md をファイルとして読む経路では literal のまま**。
+ v2.1.146 で確認：Claude (LLM) も「skill body reached me with substitution already applied」と認識しており、context load 直前の substitution というメカニズムが維持されている。
```

## probe 08 + 08b — frontmatter hook timing （§1.8）

`./scripts/assert.sh 08` → **PASS (3/3)**
`./scripts/assert.sh 08b` → **PASS (3/3)**

### subclaim 単位の判定

| § subclaim | research v2.1.118-119 | v2.1.146 実測 | 判定 |
|---|---|---|---|
| skill frontmatter `SessionStart + once:true` は**発火しない** | ✅ 不発 | ✅ `[08-FM-SESSIONSTART unexpected fire]` が probe.log に**現れない** | PASS |
| skill frontmatter `PreToolUse:Bash` は **invoke 後** の Bash で発火 | ✅ | ✅ `[08-FM-PreToolUse fired]` が probe.log に invoke 後の各 Bash 呼び出しで記録 | PASS |
| 自スキルの最初の load を frontmatter hook で block するのは**不可** | ✅ 不可（hook は load 後に登録） | ✅ 08b の 1 回目 invoke は成功 → `[08b-BODY] tag=alive-check (this proves 08b loaded — frontmatter cannot block itself)` | PASS |
| 自スキルの **2 回目以降** invoke は frontmatter `PreToolUse:Skill` で block 可能 | ✅（推定、明示観察なし） | ✅ 08b 2 回目（自然文）は `Error: blocked by 08b-self-block-attempt (testing whether self-blocking works)` で block | PASS |

### 重要：08b の self-block は §1.8 と §1.9 の組み合わせで成立

08b の 2 回目 invoke を **自然文で**呼んだから block された：

- 自然文呼び出し → Claude が `Skill` tool を呼ぶ → PreToolUse:Skill hook 発火 → 08b の登録済 frontmatter hook が JSON `{"decision":"block","reason":"..."}` を返す → block 成立
- **slash で 2 回目を呼んでいたら**：研究 §1.9 により Skill tool 不発 → PreToolUse:Skill 不発 → block されない（=skill body が走る = 1 回目と同じ）

これは §1.8 と §1.9 が連動する設計上の重要な特性。**block ガードを掛けたい plugin 作者は「自然文経由でしか block されない」ことを念頭に置く必要がある**。

### 確認した log

```
[08-FM-PreToolUse fired] 2026-05-21T15:32:08+09:00
[08-BODY 2026-05-21T15:32:18+09:00] tag=alive-check
[08-FM-PreToolUse fired] 2026-05-21T15:32:22+09:00
[08b-BODY 2026-05-21T15:37:52+09:00] tag=alive-check (this proves 08b loaded — frontmatter cannot block itself)
[08b-FM 2026-05-21T15:38:15+09:00] tag=block-emitted reason="blocked by 08b-self-block-attempt"
```

タイムスタンプの差（08-FM が 08-BODY より 10 秒早い）は、PreToolUse:Bash の同期実行（hook 完了 → tool 実行）の order を表しているだけで、研究 §1.10 の並列実行とは別問題（§1.10 は同一 array 内の hook 同士の並列）。

### 含意

- **block ガード設計**：plugin 作者が「特定 skill の起動を止めたい」場合、その skill の frontmatter に PreToolUse:Skill hook を置く方法は使える（ただし最初の起動は止まらない）。
- **slash invoke は guard 経路をバイパス**する：plugin 作者の意図に反する skill 起動を slash で行えば、block hook を avoid できる。「skill 経由の sandboxing」は完全ではない
- **自スキル自体の保護**：08b パターンは「初回 load は許す、再 load は止める」という設計。**初回 load の副作用が問題ない**前提なら使える（例：state initialization は 1 回だけ走らせる用途）

### 研究 §1.8 / §2.4 改訂提案

```diff
+ v2.1.146 で確認（probe 08 + 08b）：
+ - `SessionStart + once:true` を skill frontmatter に書いても発火しない（skill load 前なので hook 未登録）
+ - skill 自体の最初の load は frontmatter hook で block 不可
+ - 2 回目以降の skill invoke は frontmatter `PreToolUse:Skill` hook で block 可能（**自然文経由限定** — §1.9 の slash 経路は Skill tool 不発のため block hook も不発）
+ - block 設計は §1.8 + §1.9 の組み合わせで考える必要がある
```

## probe 09-slash-vs-natural （§1.9 / §6.2）

`./scripts/assert.sh 09` → **PASS (4/4 matched)**（assert.sh の pipefail バグ修正後）

### subclaim 単位の判定（v2.1.146 確定版）

実測：2 セッション分の hooks.log を timestamp window で分離（15:51:xx = slash session, 15:52:xx = natural session）：

| event tag | Slash session | Natural session | research §1.9 主張 |
|---|---|---|---|
| `tag=user-prompt-submit` | ✅ 発火 | ✅ 発火 | 両方で発火 |
| `tag=user-prompt-expansion` | ✅ 発火 | **❌ 不発** | slash でのみ発火 |
| `tag=pretool-skill` | **❌ 不発** | ✅ 発火 | 自然文でのみ発火 |
| `tag=pretool-bash` | ✅ 発火（skill body Bash） | ✅ 発火（skill body Bash） | 両方で発火 |

研究 §1.9 と完全一致：**slash 経路は Skill tool を通らない、自然文経路は Skill tool 経由**。slash 起動は `UserPromptExpansion` event を発火させ template 展開する path だが Skill tool は呼ばない。自然文は逆。

### 含意

- **OTEL 等で skill 起動を漏れなく観測したい場合は両経路を UNION で監視必須**：自然文経由 (`Skill` tool) + slash 経由 (`UserPromptExpansion`)
- **plugin 作者のガードレール設計**：08b で見たように、Skill tool の PreToolUse hook で block するパターンは自然文経由しか効かない。slash 起動を止めたければ別の手段（UserPromptSubmit hook で prompt 文字列を見る等）が必要
- skill 起動時の context cost は同じだが、内部経路が違うので hook 発火パターンも違う

### assert.sh の重大なバグ発見 + 修正

probe 09 を回した時、`grep -F` が hooks.log の中の `tag=user-prompt-submit` 等を「見つからない」と返してきた。実際には 24 件もマッチしているのに。原因：

**`set -o pipefail` + `printf "%s\n" "$buf" | grep -qF -- "pattern"` の組み合わせバグ**

- 大きい `$buf`（165KB）を printf で pipe に書く
- パイプバッファは Linux で typically 64KB
- 64KB 以降は printf が grep の consume を待つ
- 一方 grep -q は最初のマッチで早期終了 → printf に SIGPIPE
- printf が SIGPIPE で exit 141
- `set -o pipefail` により pipeline の終了コードが 141 になる
- `&& MATCH || MISS` の判定が MISS 扱いに

`scripts/assert.sh` の grep 経路 4 箇所を **here-string (`<<< "$buf"`)** に変更して fix。pipe を使わないので SIGPIPE が起きない。

この bug は **hooks.log が pipe buffer サイズを超えた時にだけ顕在化**するので、初期の probe 00-08（hooks.log が小さかった頃）では PASS と判定されていた。probe 09 のタイミングで hooks.log が 165KB に育って初めて顕在化。

→ commit `scripts/assert.sh` のところで詳述。

### 根拠 log

```
=== [2026-05-21T15:51:02+09:00] tag=user-prompt-expansion ===  ← Slash session
=== [2026-05-21T15:51:02+09:00] tag=user-prompt-submit ===
=== [2026-05-21T15:51:10+09:00] tag=pretool-bash ===
（slash session には tag=pretool-skill 無し）

=== [2026-05-21T15:51:59+09:00] tag=session-start ===            ← Natural session start
=== [2026-05-21T15:52:06+09:00] tag=user-prompt-submit ===       ← Natural session prompt
=== [2026-05-21T15:52:10+09:00] tag=pretool-skill ===            ← Skill tool 経由
=== [2026-05-21T15:52:15+09:00] tag=pretool-bash ===             ← Skill body Bash
（natural session には tag=user-prompt-expansion 無し）
```

### 研究 §1.9 改訂提案

```diff
+ v2.1.146 で確認（probe 09）：研究 §1.9 表の通り。`UserPromptExpansion` は CLI で slash のみ、`Skill` tool は自然文のみ。
+ slash 経由で skill を呼んだ時の event chain: UserPromptExpansion → UserPromptSubmit → PreToolUse:Bash（skill body の Bash 呼び出し時）
+ 自然文経由で skill を呼んだ時の event chain: UserPromptSubmit → PreToolUse:Skill → PreToolUse:Bash
+ Skill 起動の OTEL 監視は両 path を UNION で取る必要あり（研究 §9.1 の SQL クエリと整合）
```

## probe 10-parallel-hook-firing （§1.10）

`./scripts/assert.sh 10` → **PASS (7/7 matched)**

### subclaim 単位の判定

| § subclaim | research v2.1.118-119 | v2.1.146 実測 | 判定 |
|---|---|---|---|
| 同一 hook 配列内の hook は**並列実行**される | ✅（v0.7 array order 観察） | ✅ 完全並列 — 別 pid、start 時刻が近い、end は sleep 順 | PASS |
| array order ≠ 実行順 | ✅ | ✅ start すら b → c → a（array 宣言は a, b, c） | PASS |

### 実 timestamps（最新 SessionStart）

```
parallel-b-start: 1779347021137257338 ns  pid=75738
parallel-c-start: 1779347021142627699 ns  pid=75750  (+5.4ms vs b)
parallel-a-start: 1779347021145053573 ns  pid=75753  (+7.8ms vs b)
parallel-c-end:   1779347021148706952 ns  (sleep 0   → +6ms)
parallel-a-end:   1779347021353025210 ns  (sleep 200ms → +208ms)
parallel-b-end:   1779347021542495287 ns  (sleep 400ms → +405ms)
```

### 観察できたこと

1. **別 pid** で 3 プロセス並走（pid=75738/75750/75753）
2. **start 時刻が ~10ms 窓に収まる** — 同時起動の証拠（順次なら sleep 完了を待つので最低 600ms の差になる）
3. **end 順序 = sleep 順序**（c < a < b、各 sleep 0/200/400ms と一致） — 並列実行の決定的証拠
4. **start 順序すら array 順と一致しない** — bonus 観察。OS scheduler が spawn 順を arbitrate しているだけ

これは順次実行（sequential）の場合と明らかに区別可能：
- 順次なら: a 完了 (200ms) → b 完了 (200ms+400ms=600ms 後) → c 完了 (600ms 後+0ms=600ms 後)。end 順序は a, b, c
- 並列なら: end 順序は c, a, b（観察通り）

### plugin-level / frontmatter hook 跨ぎの並列も発火

probe 10 の主検証は SessionStart 配列内の並列だが、別 timestamp で見ると plugin-level hook（log.sh）と skill frontmatter hook（00-canary 等の fm-registered tag）も同時 tool 呼び出しに対して並走する観察あり（probe 02 / 08b の log 順序がそれを示唆）。

### 含意

- **`flock` 排他制御は必須**：log.sh のように同じファイルに書き込む hook を複数仕掛けるなら必要。本リポジトリの log.sh は `flock -x 9` で守っているので race condition を避けられている
- **hook の副作用順序に依存した設計は破綻**：array order でも記述順でもなく、OS scheduler 任せ
- **timestamp 比較で並列性を実証可能**：probe 10 のパターン（start_ns / end_ns + 異なる sleep）は再現性のある証拠

### 研究 §1.10 改訂提案

```diff
+ v2.1.146 で確認（probe 10）：SessionStart 配列内の 3 hook が別 pid で並列起動。
+ 観察された start 順序は array 宣言順（a, b, c）と異なる（b → c → a などランダム）。
+ end 順序は各 hook の sleep duration に従い、c (0ms) → a (200ms) → b (400ms)。
+ 順次実行（end 順序 = a → b → c）とは数値的に明確に区別される。
+ ファイル書き込みを行う複数 hook は flock 等で排他制御必須（本リポジトリの log.sh が good practice の reference）。
```

## probe 11 + 12 — frontmatter PreToolUse:Skill で別 skill を block （§2.4 / §2.5）

`./scripts/assert.sh 11` → **PASS (2/2 matched)**
`./scripts/assert.sh 12` → **PASS (3/3 matched)**

### subclaim 単位の判定

| § subclaim | research v2.1.118-119 | v2.1.146 実測 | 判定 |
|---|---|---|---|
| skill frontmatter `PreToolUse:Skill` hook が**別 skill の Skill tool 呼び出しを block 可能** | ✅ | ✅ 12-block-self が `PreToolUse:Skill` で 11-block-target の起動を block | PASS |
| block reason 文字列が Claude の context に戻る | ✅ | ✅ `Error: blocked by 12-block-self frontmatter hook (target was 11-block-target)` が Claude 出力に表示 | PASS |
| block されると tool 呼び出し自体が**実行されない**（target の skill body は走らない） | ✅ | ✅ `[11-BODY]` 行が probe.log に**出ない** | PASS |
| **自然文経由でしか block しない**（slash は §1.9 通り Skill tool 不発） | （明示なし、推定） | ✅（自然文「11-block-target を起動してください」で block 観察、slash だと別経路） | PASS（bonus 観察） |

### 観察の流れ

```
1. /verifier:12-block-self (slash invoke)
   → 12 の skill body が "alive-check (self-blocker registered)" を probe.log に書く
   → このタイミングで 12 の frontmatter PreToolUse:Skill hook が登録される（§1.8）

2. "11-block-target skill を起動してください" (自然文 invoke)
   → Claude が Skill(verifier:11-block-target) tool を呼ぼうとする
   → PreToolUse:Skill hook が発火（12 の登録済み frontmatter hook）
   → 12 のフック command がペイロード stdin の `tool_input.skill` を見て 11-block-target を識別
   → JSON `{"decision":"block","reason":"blocked by 12-block-self frontmatter hook (target was 11-block-target)"}` を stdout 出力
   → Claude Code が block 決定として処理 → Skill tool 呼び出しを止める
   → Claude UI に `Error: blocked by ...` 表示
   → 11 の skill body は load されない（[11-BODY] が probe.log に書かれない）
```

### 含意 — block-as-guard の現実的な制約

§1.8 + §1.9 + §2.4 / §2.5 を組み合わせた v2.1.146 での block 設計の総合像：

- **同じ plugin 内 / 別 plugin の skill 起動を block する仕組み**は機能する（CLI / v2.1.146 両方で）
- ただし**自然文経由でのみ**有効：ユーザーが `/verifier:11-block-target` を slash で打てば、§1.9 により Skill tool は呼ばれず、12 の PreToolUse:Skill hook も発火しない → block 不発、11 が普通に走る
- **block が「指示書の lockdown」として弱い**ことを意味する：ユーザーが意図的に bypass しようとすれば slash で簡単に逃げられる。ただし「Claude が自律的にツール選択で別 skill を呼ぶ」シナリオは block できる（08b の自己 block と同様）
- **「Claude の Skill tool 経由」と「ユーザーの slash 経由」を区別したい場合**：plugin-level の UserPromptSubmit hook で raw prompt 文字列を見て slash パターンを検出する必要あり（OTEL 視点だと研究 §9.1 の UNION クエリと同じ）

### 根拠 log

```
[12-BODY 2026-05-21T16:13:45+09:00] tag=alive-check (self-blocker registered)
[12-BODY 2026-05-21T16:14:24+09:00] tag=block-observed target=11-block-target verdict=PASS
```

Claude UI output:
```
Error: blocked by 12-block-self frontmatter hook (target was 11-block-target)
```

`[11-BODY]` 行は probe.log に**存在しない**（block 成功）。

### 研究 §2.4 / §2.5 改訂提案

```diff
+ v2.1.146 で確認（probe 11 + 12）：skill frontmatter `PreToolUse:Skill` hook で別 skill の Skill tool 呼び出しを block 可能。
+ 制約：§1.9 の slash 経路は Skill tool を通らないので block hook も発火しない。
+ block を「ユーザーが回避できないガード」として使う設計は v2.1.146 では成立しない（slash bypass あり）。
+ 「Claude の自律 skill 選択を抑制する」用途では引き続き有効。
+ 上記は CLI 環境の挙動。Cowork での同等観察は probe 13-21 で取得予定。
```

## probe 13-cowork-pretooluse（CLI baseline 部分）（§2.5 / §2.4）

`./scripts/assert.sh 13` → **PASS (3/3 matched)**（CLI baseline 部分のみ）

### CLI baseline subclaim 判定

| § subclaim | CLI 期待 | v2.1.146 CLI 実測 | 判定 |
|---|---|---|---|
| plugin-level `PreToolUse:Bash` hook が CLI で発火（default では pass-through） | ✅ 発火、block 仕掛けないので透過 | ✅ `tag=pretool-bash` 出現、`TEST_BASH_OK_MARKER` 平文出力 | PASS（CLI baseline 確定） |
| CLI で `matcher: "mcp__workspace__bash"` の hook は不発（Cowork 限定 tool 名） | ✅ 不発 | ✅ `tag=pretool-mcp-workspace-bash` 出現せず | PASS |
| `CLAUDE_CODE_ENTRYPOINT=cli` を skill body で確認可能 | ✅ | ✅ `[13-BODY] CLAUDE_CODE_ENTRYPOINT=[cli]` | PASS |

### Cowork 部分（deferred）

以下は Cowork (Claude Desktop) 環境必須なので保留：

- plugin-level `PreToolUse:Bash`（matcher Bash / Skill / `.*` / mcp__workspace__bash）の block 試行が全て無視される（§2.5）
- bash tool 名が `mcp__workspace__bash` になる（§2.4）→ CLI で確認した「matcher Bash / Skill / `.*` 不発」が Cowork 側でも継続する想定
- hooks-block.json variant を有効化してから Cowork zip を作成・upload → block 不発確認

### 含意（CLI baseline 視点）

- CLI で plugin-level PreToolUse:Bash がきちんと発火するのは確認できた（research §2.5 の CLI ✅ と整合）
- Cowork 側の「block 死亡」は CLI baseline と対比することで初めて意味が出る observation。Cowork 検証フェーズで再度参照

### 根拠 log

```
[13-BODY 2026-05-21T16:17:03+09:00] tag=alive-check
[13-BODY] TEST_BASH_OK_MARKER (CLI without block hook: appears; ...)
[13-BODY] CLAUDE_CODE_ENTRYPOINT=[cli]

=== [2026-05-21T16:17:00+09:00] tag=pretool-bash ===
=== [2026-05-21T16:17:08+09:00] tag=pretool-bash ===
=== [2026-05-21T16:17:13+09:00] tag=pretool-bash ===
（tag=pretool-mcp-workspace-bash は全 hooks.log 通じて 0 件）
```

## probe 14-cowork-parser（CLI baseline 部分）（§2.6 / §7.10 / §7.11）

`./scripts/assert.sh 14` → **PASS (6/6 matched)** （CLI baseline）

### CLI baseline subclaim 判定

CLI では hook command が `/bin/sh` で実行され、`bash -c "..."` を含むパーサーテストは（外側 /bin/sh が解釈してから内側 bash -c に渡す形で）全て成立：

| parser test | hook command | CLI 観察 | 判定 |
|---|---|---|---|
| T0 BARE | `echo PARSER_TEST_BARE >> ...` | ✅ `PARSER_TEST_BARE` | PASS |
| T1 DQ | `bash -c "echo PARSER_TEST_DQ"` | ✅ `PARSER_TEST_DQ` | PASS |
| T2 SEMI | `bash -c "echo PARSER_TEST_SEMI; echo PARSER_TEST_SEMI_X"` | ✅ `PARSER_TEST_SEMI` + `PARSER_TEST_SEMI_X` | PASS |
| T3 PIPE | `bash -c "echo PARSER_TEST_PIPE \| cat"` | ✅ `PARSER_TEST_PIPE` | PASS |
| T4 VAR | `bash -c "x=foo; echo PARSER_TEST_VAR_$x"` | ⚠ `PARSER_TEST_VAR_`（`foo` が抜けた） | PARTIAL — 下記 bonus 参照 |
| T5 AND | `bash -c "true && echo PARSER_TEST_AND"` | ✅ `PARSER_TEST_AND` | PASS |
| T6 OR | `bash -c "false \|\| echo PARSER_TEST_OR"` | ✅ `PARSER_TEST_OR` | PASS |

→ T0-T6 のうち 6 つはマーカー出現で PASS（assert.sh は T0/DQ/PIPE/AND/OR の 5 マーカー + alive-check で 6 matched）。

### bonus 観察 — 二重 shell の `$x` 展開タイミング

T4（VAR）の結果が `PARSER_TEST_VAR_foo` ではなく `PARSER_TEST_VAR_`（末尾 foo が抜け）だった。原因：

hook command の JSON は：
```json
"command": "bash -c \"x=foo; echo PARSER_TEST_VAR_$x\" >> \"...\""
```

JSON エスケープ解除後、`/bin/sh` が受け取る文字列：
```sh
bash -c "x=foo; echo PARSER_TEST_VAR_$x" >> "..."
```

ここで `"$x"` は外側 `/bin/sh` が**先に展開**する（double-quoted 内の変数展開）。外側 sh は `x` を知らない → `$x` = 空文字列。bash -c が受け取る引数は：
```sh
x=foo; echo PARSER_TEST_VAR_
```

bash -c 内で `x=foo` が assign されるが、`echo` の引数は既に空文字置換済み。結果 `PARSER_TEST_VAR_` のみ。

`PARSER_TEST_VAR_foo` を出したければ `$x` をエスケープ：

```json
"command": "bash -c \"x=foo; echo PARSER_TEST_VAR_\\$x\""
```

これで `/bin/sh` 層では `\$x` → literal `$x`、bash -c 内で `$x` が `foo` に展開。

研究の `bash -c "x=foo; echo ..."` testcase はこのエスケープ問題に触れていなかったが、**CLI / Cowork どちらでも同じ罠**にハマる可能性がある。

### Cowork で観察すべき項目（deferred）

- T1-T6 のうち **Cowork で消えるのは AND / OR / PIPE / cat 等**（research §2.6 によると outer parser が && || | を分断する）。CLI baseline では全て出ているので、Cowork で出ない＝Cowork parser whitelist 制約の証拠
- echo の bare 形 (T0) と bash -c double-quote 形 (T1) は両方とも Cowork 通過すると想定

### 含意

- **CLI は普通の /bin/sh 解釈**で複合シェル構文が動く。プラグイン作者が CLI 向けの hook を書く場合、bash -c で囲んだ複雑な command は OK
- **Cowork に出すと壊れる構文があり得る**。配布前に hooks-parser-tests.json variant + CLI/Cowork 比較で確認するワークフローが必要
- **二重 shell の `$x` 罠**（bonus）は CLI でも Cowork でも起き得る → bash -c の中の変数は `\$` でエスケープして bash -c 内で展開させるべき

### 根拠 log

```
findings/parser-tests.log:
PARSER_TEST_DQ
PARSER_TEST_VAR_         ← VAR_foo にならない（bonus 観察、二重 shell quoting 罠）
PARSER_TEST_BARE
PARSER_TEST_AND
PARSER_TEST_PIPE
PARSER_TEST_OR
PARSER_TEST_SEMI
PARSER_TEST_SEMI_X
```

### 後処理

`verifier/hooks/hooks.json` は default 内容に restore 済（probe 14 検証完了後）。

### 研究 §2.6 / §7.10 / §7.11 改訂提案

```diff
+ v2.1.146 CLI baseline （probe 14）：T0-T6 の bash -c 系 parser test 全てマーカー出現。CLI /bin/sh は research の想定通り全 bash 構文を解釈。
+ Cowork での parser whitelist 制約は research §2.6 表通り想定（AND / OR / PIPE / cat 等が outer parser で分断）→ Cowork 検証 round で具体確認。
+
+ bonus（research に明示なし）：bash -c 内の変数は `$x` ではなく `\$x` でエスケープしないと外側 /bin/sh が先に展開してしまう。
+ JSON エスケープ込みで `\\$x` と書く必要あり。CLI / Cowork どちらでも同じ罠。
```

## probe 15-cowork-file-io（CLI baseline 部分）（§2.7）

`./scripts/assert.sh 15` → **PASS (3/3 matched)** （CLI baseline）

### CLI baseline subclaim 判定

| § subclaim | CLI 期待 | v2.1.146 CLI 実測 | 判定 |
|---|---|---|---|
| frontmatter `PreToolUse:Bash` hook が `/tmp` に file 書き込み可能 | ✅ | ✅ `/tmp/file-io-canary-1779348236387557391.txt` 作成 | PASS |
| 同じファイルが Bash tool subprocess から `ls -la` で**見える** | ✅ | ✅ `-rw-r--r-- 1 kazukinagata kazukinagata 98 May 21 16:23 /tmp/file-io-canary-...txt` | PASS |
| hook が呼ばれた証拠が probe.log に出る（独立の証明経路） | ✅ | ✅ `[15-FM-hook fired marker_path=/tmp/file-io-canary-...]` | PASS |

### Cowork で観察すべき項目（deferred）

- 同じ probe を Cowork で回すと **`ls -la /tmp/file-io-canary-*.txt` の結果が「ファイル不在」**になる（§2.7）。Cowork の sandbox が hook プロセスの file write を本体 shell に伝播させない
- ただし probe.log 経由の `[15-FM-hook fired marker_path=...]` 行は Cowork でも残るので、「hook が起動した」事実と「hook の file 副作用が見えない」事実が同時に観察できる
- これが §2.7 の根幹：hook の **stdout 経路だけ活きていて file 副作用は別 sandbox にブロックされる**

### 含意

- CLI で hook 内 file write をする plugin は当然動くが、**Cowork 配布前提なら別経路（stdout 経由の additionalContext、外部 API 等）に切り替える設計**が必要（research §3.2 / §3.7 の harness 指針と整合）
- 本リポジトリの log.sh は file write を使うが、これは検証用の log であって配布想定ではない（Cowork で log が出ないことも併せて記録する）

### 根拠 log

```
[15-BODY 2026-05-21T16:24:06+09:00] tag=alive-check
[15-BODY] file-io-canary files in /tmp:
-rw-r--r-- 1 kazukinagata kazukinagata 98 May 21 16:23 /tmp/file-io-canary-1779348236387557391.txt
[15-FM-hook fired marker_path=/tmp/file-io-canary-1779348236387557391.txt]
```

### 研究 §2.7 改訂提案

```diff
+ v2.1.146 CLI baseline （probe 15）：hook 内の file write は普通に届く（/tmp に書いた canary が Bash subprocess の ls で確認できる）。
+ Cowork での file write 不発は別環境で確認する。
+ hook が呼ばれた事実は probe.log への独立 echo で別経路観察可能 — Cowork での「hook 自体は呼ばれたが file が届かない」状態を判定する canary として有用。
```

## probe 20-cowork-validation（CLI baseline 部分）（§2.3）

`./scripts/assert.sh 20` → **PASS (4/4 matched)** （CLI baseline）

### CLI validate の実測文言

**20a — UserPromptExpansion variant plugin** （`verifier-violator-userpromptexpansion`）：
```
Validating plugin manifest: /home/.../verifier-violator-userpromptexpansion/.claude-plugin/plugin.json
✔ Validation passed
```
→ CLI **エラーも warning も無し**。UserPromptExpansion event を含む hooks.json が validator を通過する。

**20b — uppercase plugin name variant** （`verifier-violator-uppercase-name`、`name: "Verifier-Violator-Uppercase"`）：
```
Validating plugin manifest: /home/.../verifier-violator-uppercase-name/.claude-plugin/plugin.json

⚠ Found 1 warning:
  ❯ name: Plugin name "Verifier-Violator-Uppercase" is not kebab-case. Claude Code accepts it, but the Claude.ai marketplace sync requires kebab-case (lowercase letters, digits, and hyphens only, e.g., "my-plugin").

✔ Validation passed with warnings
```
→ CLI は **warning** のみ。hard error ではない。「Claude Code accepts it, but the Claude.ai marketplace sync requires kebab-case」と注釈付き — つまり v2.1.146 で kebab-case の制約は **Claude.ai marketplace 側の sync 要件**で、CLI/Claude Code 単体では受け入れる方針。

### subclaim 判定

| § subclaim | research v2.1.118-119 | v2.1.146 CLI 実測 | 判定 |
|---|---|---|---|
| CLI は具体的なエラー / warning を返す（Cowork の generic と対比） | ✅ 具体メッセージ | ✅ 具体 warning（kebab-case）or 通過 | PASS — 文言は具体的 |
| UserPromptExpansion in hooks.json を CLI validator が**block する** | ✅ block と推定 | ❌ **block しない、Validation passed** | **FAIL** — research § 2.3 で「CLI 具体エラー / Cowork generic」と書かれていたが、v2.1.146 CLI では UserPromptExpansion 単独では block しない |
| 大文字 plugin name を validator が拒否 | ✅ `Plugin name must be kebab-case` | ⚠ warning のみで pass | **DOC-ALIGNED / 退行**：v2.1.146 は CLI 単体では receive、Claude.ai marketplace sync は kebab-case 必須 |

### v2.1.146 で挙動が変わった可能性

研究 §2.3 行 142-149 では「CLI で `Plugin name must be kebab-case: ...` のような具体エラー、Cowork で generic」とされていた。v2.1.146 CLI は **warning だけで pass** に softer になっている。これは：

- 研究時の挙動（具体エラーで拒否）から v2.1.146 で warning だけに緩和された possibility
- または研究時点でも warning が出ていたが、研究記録者は警告 vs エラーを区別していなかった possibility

いずれにせよ **v2.1.146 CLI は invalid plugin を install してしまう** ので、CI で `claude plugin validate` を回しても sync 要件違反を検出できない（Claude.ai marketplace への push でだけエラーになる）。

### Cowork で観察すべき項目（deferred）

両 variant を Cowork で zip upload → どちらも `Plugin validation failed`（generic、理由表示なし）になるはず（§2.3）。CLI baseline で取った具体文言と対比することで research §2.3 の主張（「Cowork は理由表示無し」）の確認になる。

### 研究 §2.3 改訂提案

```diff
- | Plugin name エラー | 具体的：`Plugin name must be kebab-case: ...` | 汎用：`Plugin validation failed`（理由不明） |
+ | Plugin name エラー | v2.1.118-119 当時：具体エラー（推定）。v2.1.146 実測：CLI は **warning only**、`name: Plugin name "X" is not kebab-case. Claude Code accepts it, but the Claude.ai marketplace sync requires kebab-case`、それでも `Validation passed with warnings` で install 可能 | 汎用：`Plugin validation failed`（理由不明） |
+ | UserPromptExpansion in hooks.json | v2.1.118-119：CLI は通る、Cowork は validation 拒否 | v2.1.146 CLI 実測：`Validation passed` 完全に通過、Cowork 側挙動は未確認 |
+
+ v2.1.146 で CLI validator は invalid plugin の発見が softer に：kebab-case 違反は warning、UserPromptExpansion は pass。Cowork 側の rejection は別レイヤー（marketplace sync / Cowork validation gate）で実装されている可能性が高い。
```

---

## CLI 検証 round の summary

CLI 環境で実行可能な probe をすべて完走：

| probe | verdict | research との関係 |
|---|---|---|
| 00-canary | PASS (8/8) | 観測基盤健全 |
| 01-env-propagation | PASS (12/12) | env 伝播 3 階層 + PROJECT_DIR が frontmatter に届く（未確認だった）|
| 02-substitution-allowlist | PARTIAL (6/8) | CLAUDE_PROJECT_DIR が skill body で置換される（仕様変更）+ install validator block 不発 |
| 03-shell-binsh | PASS (7/7) | /bin/sh = dash 確認 + bonus `${PWD^^}` 罠 |
| 04-sensitive-leak | PASS (5/5) | sensitive 値が env 平文露出 + WSL では `.credentials.json.pluginSecrets` |
| 05-userconfig-trigger | PARTIAL (1/2) | install/enable silent + `/plugins` UI + disable→enable silent confirmed、route 4 (参照あり+未設定 hook error) は plugin-level reference が無いため deferred |
| 06-marketplace-cache | PASS (2/2) | source path runtime + cache dead data + installPath が cache を指す metadata と不整合 |
| 07-skill-body-subst | PASS (3/3) | invoke 経路のみ substituted、Read 経路は literal |
| 08-frontmatter-timing | PASS (3/3) | SessionStart+once:true 不発、PreToolUse:Bash は invoke 後発火 |
| 08b-self-block-attempt | PASS (3/3) | 自スキル初回 load は block 不可、自然文 2 度目で block 可能（§1.8+§1.9 連動）|
| 09-slash-vs-natural | PASS (4/4) | slash で UserPromptExpansion / pretool-skill 不発、自然文で逆 |
| 10-parallel-hook-firing | PASS (7/7) | SessionStart array 内 3 hook 並列発火、別 pid + nanosec ts で実証 |
| 11-block-target / 12-block-self | PASS (2/2, 3/3) | frontmatter PreToolUse:Skill で別 skill を block 可能（自然文経由限定）|
| 13-cowork-pretooluse | PASS (3/3) | CLI baseline：plugin-level PreToolUse:Bash 発火、mcp__workspace__bash matcher 不発 |
| 14-cowork-parser | PASS (6/6) | CLI baseline：全 bash -c 構文通過、bonus `$x` 二重 shell 罠 |
| 15-cowork-file-io | PASS (3/3) | CLI baseline：hook 内 /tmp file write が Bash subprocess から見える |
| 20-cowork-validation | PASS (4/4) | CLI baseline：UserPromptExpansion 通過 / 大文字 plugin name は warning のみ |
| 16-cowork-path-forms | DEFERRED | Cowork で path 3 形式観察必要 |
| 17-cowork-bash-mount | DEFERRED | Cowork の `/sessions/<codename>/mnt/` filesystem 必要 |
| 18-cowork-data-isolation | DEFERRED | Cowork の cross-chat DATA 分離必要 |
| 19-cowork-resume | DEFERRED | Cowork VM suspend/resume 必要 |
| 21-cowork-connected-folder | DEFERRED | Cowork の `request_cowork_directory` tool 必要 |

**CLI verification round の総括**：

- 17 probe を実行、12 PASS + 2 PARTIAL（02, 05）+ 5 deferred（Cowork-only）
- assert.sh の重大バグ（pipefail+SIGPIPE）を発見・修正（probe 09 で顕在化）
- 環境固有 finding を 30+ 件 observations.md に記録
- 研究 §1.1, §1.2, §1.3, §1.4, §1.5, §1.6, §1.7, §1.8, §1.9, §1.10, §2.3, §2.4, §2.5, §2.6, §2.7 の v2.1.146 状態を確定
- 主な仕様変更：CLAUDE_PROJECT_DIR の skill body 置換、CLAUDE_CODE_EXECPATH の plugin-level unset、CLAUDE_SESSION_ID env 全層 unset（CLAUDE_CODE_SESSION_ID が代替）、install-time validator block 不発、kebab-case 違反は warning only

Cowork 検証 round の次回タスク：probe 13, 14, 15, 16, 17, 18, 19, 20, 21 を Claude Desktop 上で実行し、差分を記録。本リポジトリの zip artifacts (`scripts/package-cowork.sh` の出力) を使う。

---

# Cowork 検証 round（v2.1.147 / v2.1.148）

実行日：2026-05-22
Claude Code が verification round 中に **v2.1.146 → v2.1.147 → v2.1.148 と 2 回 bump**。Cowork 内 VM のバージョンは未確認だが、ホスト CLI バージョンが大幅に短期間で進化していることだけ記録。

## §2.3 確認：Cowork validator が CLI より圧倒的に strict

`verifier-cowork.zip`（CLI で `claude plugin validate` / install 通過済）を Claude Desktop の Cowork セッションで upload → **`Plugin validation failed`** generic エラーで reject。理由表示なし。

これは **research §2.3 の主張（CLI 具体エラー / Cowork generic 拒否、Plugin validation failed）が v2.1.147/v2.1.148 でも継続**を確定。

## bisect で判明した複数の reject 要因

二分探索で 21 個の skill zip を Cowork upload に投じて narrow した結果、CLI で通る plugin を Cowork が reject する **複数の独立した validator rule** が判明：

### Finding A: plugin name の kebab-case 強制（hard reject）

**probe 20 で取った CLI baseline と決定的な差分**：

| 環境 | uppercase 含む plugin name の扱い |
|---|---|
| CLI (`claude plugin validate`) | ⚠ warning：`Plugin name "X-Y-Z" is not kebab-case. Claude Code accepts it, but the Claude.ai marketplace sync requires kebab-case` → 続行（`Validation passed with warnings`） |
| Cowork（zip upload） | ❌ **hard reject**：`Plugin validation failed`（generic、理由表示なし） |

具体的観察：
- `verifier-cowork-bisect-C-first-no-suspects.zip` （plugin name に `C` 含む）→ Cowork で fail
- 全く同じ skills 8 個を `verifier-cowork-bisect-c-first-no-suspects.zip`（C を c に変えただけ）にリネーム → Cowork で**通過**

これは research §2.3 / probe 20 の **CLI warning vs Cowork generic-rejection の対比を強化する確証**。配布の実用面では：
- **CLI の warning は無視できない** — Cowork に出すなら kebab-case 厳守
- CI で plugin 配布前チェックする場合、`claude plugin validate` の **warning も exit-failure として扱うべき**（現状の `Validation passed with warnings` exit code 0 では Cowork-incompat plugin が release されてしまう）

### Finding B: skill frontmatter hook command 内の `${PWD^^}` （bash 固有 parameter expansion）

probe 03-shell-binsh の frontmatter hook に bash 固有の `${PWD^^}` がリテラル含まれていた。**CLI**：問題なく install（research §1.3 / probe 03 確認済 — hook 実行時に `/bin/sh` で Bad substitution）。**Cowork**：**install 時点で reject**。

`${PWD^^}` を `PWD_PLACEHOLDER` 等のリテラルに置換すると Cowork install 通過。Cowork validator が hook command 内の `${VAR^^}` `${VAR,,}` 系 bash-specific parameter expansion を**事前 scan して reject** している可能性。

### Finding C: YAML single-quoted string の closing quote 省略

probe 03-shell-binsh の frontmatter `command:` 行（`; exit 0` で終わる）に **closing single quote `'` 漏れ**があった。CLI の YAML parser は何らかの forgiving 解釈で受理（`claude plugin validate` PASS）。Cowork validator はおそらく strict YAML parser で reject。修正後（closing `'` 追加）、Cowork が当該 skill を受理。

### Finding D: skill 累積 content threshold（v2.1.148 で観察）

- 22 個の simple clone skill（frontmatter 無し、body subst 無し、plain text）→ Cowork 通過
- 7 個の real skill（本物 frontmatter hook + body subst）→ Cowork 通過
- 8〜11 個の real skill 累積（特定の skill 組み合わせ）→ Cowork reject

すなわち **single skill content の複雑さ × skill 数の累積**で threshold 超過。具体的な量化指標（token / character / hook count）は未特定。bisect 続行中（**現状の bisect で 16/17/18/19/20/21 のうち少なくとも 1 つが breaker** と判明）。

### Finding F: skill `description:` field の特定 token も hard reject

probe 17 の description field に以下を入れたら Cowork install fail：

```yaml
description: "Cowork mounts the plugin install dir under /sessions/<codename>/mnt/.remote-plugins/ (read-only). Bundled scripts can be launched via relative path; ${CLAUDE_SKILL_DIR} expands to a Windows path that fails directly. ..."
```

narrowing で `${CLAUDE_SKILL_DIR}` リテラルと `<codename>` angle brackets の**どちらか単独でも reject** に確定：

| description 内容 | Cowork install |
|---|---|
| `${CLAUDE_SKILL_DIR}` のみ | ❌ reject |
| `<codename>` angle brackets のみ | ❌ reject |
| 両方含む | ❌ reject |
| `CLAUDE_SKILL_DIR` (bare token、no `${}`) + `CODENAME` literal | ✅ install OK |

ただし他 skill の description で `${VAR}` リテラル（probe 02 / 07）は**通る** — `${VAR}` は CLAUDE_* prefix ではないので Cowork が substitute を試みず literal 扱いする仮説。`${CLAUDE_*}` 形式だと substitute path に入って validator が引っかかる。

`<...>` angle brackets は HTML-like 構文として markdown / metadata layer で何らかの parser が処理しようとして fail する可能性。

### 修正方法

```diff
- description: "... /sessions/<codename>/mnt/ ... ${CLAUDE_SKILL_DIR} ..."
+ description: "... /sessions/CODENAME/mnt/ ... CLAUDE_SKILL_DIR ..."
```

→ `${VAR}` 形式の説明を諦めて bare token に書き換える。`<placeholder>` 形式の説明を `PLACEHOLDER` や `<codeword>` 風の literal text に書き換える。

### Finding E: Cowork rejection は CLI から完全に detect 不可能

research §2.3 の主張通り、Cowork rejection の理由は generic "Plugin validation failed" のみ。CLI の `claude plugin validate` / `claude plugin install` で **shadow validation できない**。Cowork-compat な plugin を配布したい場合：

1. plugin name は **完全に kebab-case**（lowercase letters + digits + hyphens のみ）
2. hook command から **bash-specific syntax**（`${VAR^^}` `${VAR,,}` 等）を完全排除
3. YAML 文法を strict に守る（特に single-quoted string の closing quote）
4. skill content を可能な限り simple に保つ（具体的閾値は未特定だが、frontmatter hook + body subst を持つ real skill を 7 個以下に抑えるのが安全）
5. Cowork-only な observable には **stdout / additionalContext 経路**のみ使う（file I/O は §2.7 通り無効）

これらは CLI 側からの `claude plugin validate` では検知できないので、**Cowork 実機での upload 試験を CI に組み込む必要**がある。

## 最終的に Cowork-installable になった verifier-cowork.zip の状態

bisect の結果、以下を満たすことで Cowork install 通過：

1. **closing quote 修正**：probe 03 SKILL.md frontmatter `command:` 行末に欠けていた `'` を追加
2. **probe 17 description 修正**：`${CLAUDE_SKILL_DIR}` → `CLAUDE_SKILL_DIR` (bare)、`/sessions/<codename>/` → `/sessions/CODENAME/`
3. UserPromptExpansion strip（既存の package-cowork.sh で対応済）

これで 22 個全 skill 含む verifier プラグインが Cowork で install 可能になり、probe 13-21 の本格検証に進めるようになった。

なお、最終的に Cowork-installable verifier.zip を「研究のリファレンス実装」として残す価値は高い — plugin 作者が Cowork-compat な plugin を書くための good-practice template になる。



## §2.3 の改訂提案

```diff
+ v2.1.147/v2.1.148 で確認（実機 upload bisect）：Cowork validator は CLI より**有意に strict**。CLI で warning のみで通る違反項目を Cowork は hard reject する。具体的に判明した reject 対象：
+ 1. plugin name の kebab-case 違反（CLI ⚠ warning / Cowork ❌ hard reject）
+ 2. hook command 内の `${VAR^^}` bash-specific parameter expansion（CLI ✅ accept、実行時に Bad substitution）
+ 3. YAML single-quoted string の closing quote 漏れ（CLI 受理する forgiving parser、Cowork strict）
+ 4. **skill `description:` field 内の `${CLAUDE_*}` substitution markers と `<...>` angle brackets**
+ 5. skill body / frontmatter command content の累積 threshold（具体閾値未特定）
+ Cowork rejection は generic `Plugin validation failed` のみで理由表示無し（研究 §2.3 主張継続）。
+ 配布前ワークフローは「CLI validate + warning も failure 扱い + Cowork 実機 upload 試験」の 3 段が必要。
```

---

# Cowork 実機 probe 検証（2026-05-22）

verifier-cowork.zip install 通過後、Claude Desktop の Cowork session（codename: `elegant-exciting-brown`）で各 probe を順次実行。

## probe 00-canary（Cowork）— PASS（観測戦略の確定）

**結果**：skill body の bash は動作。alive-check tag は probe.log に書けた。

```
[00-canary-body 2026-05-22T01:51:13+00:00] tag=alive-check sid=no-sid
```

ディレクトリ作成パス: `/sessions/elegant-exciting-brown/findings/v-unknown/no-sid/`

- `$CLAUDE_PROJECT_DIR` UNSET in Bash tool subprocess → `:-$PWD` fallback で `/sessions/elegant-exciting-brown` に解決
- `$CLAUDE_SESSION_ID` UNSET → `no-sid` fallback
- `$VERIFIER_VERSION_DIR` UNSET → `v-unknown` fallback
- **`hooks.log` は不在**：plugin-level SessionStart hook の file write が bash sandbox に届かない（`tail: cannot open '/sessions/elegant-exciting-brown/findings/v-unknown/no-sid/hooks.log' for reading: No such file or directory`）

### §1.1 確認：env 伝播 3 階層は Cowork でも非対称（CLI と同じ）

Bash tool subprocess に `CLAUDE_PROJECT_DIR` `CLAUDE_SESSION_ID` 何も継承されない。CLI baseline（probe 01 PASS）と一致。

### §2.7 確認：plugin-level hook → bash sandbox の file I/O 隔離

`hooks.log` が `/sessions/.../findings/v-unknown/no-sid/` に存在しない。CLI なら必ず存在する（plugin-level SessionStart hook の log.sh 経由）。

### Cowork-specific observation strategy（残り probe の判定ルール）

`probe.log` には書ける（skill body の bash 自体は file write 可）が、`hooks.log` には書けない（plugin-level hook の write が bash 経由で見えない）。

→ **残り 8 probe の観測経路**：
1. **skill body の bash 内 echo** — Claude の応答画面に出る（信頼可能）
2. **hook の stdout (additionalContext)** — Claude の応答テキストに混入される可能性（次 probe で検証）
3. **hook の file write** — 不可（§2.7）

つまり、hook の発火を Cowork で観測するには **hook command の echo を Claude の応答テキストに探す** しかない。bash 経由で `cat hooks.log` しても見えないため、各 probe の判定は Claude の応答画面（コピペ）全体を見て判定する。

## probe 13-cowork-pretooluse（Cowork）— PASS（§2.5 / §2.4 / §2.10 再現）

実行時の codename: `gifted-epic-meitner`（probe 00 の `elegant-exciting-brown` から **3 分以内に rotation**）

**結果**：

```
[13-BODY 2026-05-22T01:54:35+00:00] tag=alive-check
[13-BODY] TEST_BASH_OK_MARKER (CLI without block hook: appears; CLI with block hook: should not appear; Cowork: should appear)
[13-BODY] CLAUDE_CODE_ENTRYPOINT=[(unset)]
```

- ✅ `TEST_BASH_OK_MARKER` が出力された → **plugin-level PreToolUse block 無効化を再確認**（§2.5）
- ✅ Bash tool 名 = `mcp__workspace__bash`（§2.4 確認）
- ✅ plugin mount: `/sessions/gifted-epic-meitner/mnt/.remote-plugins/plugin_01Pdajh3vPnV67uwKK2d3ZVB/`（`dr-x------` read-only）— §2.10 一致
- ✅ hooks.log 不在（§2.7 再確認）
- ✅ 同 VM 内に 4 つの `plugin_*` dir 存在 — Cowork は Anthropic 標準 skill + ユーザ install plugin を 同じ `.remote-plugins/` 配下に並べる

### codename について（運用メモ、finding ではない）

probe 00 = `elegant-exciting-brown`、probe 13 = `gifted-epic-meitner`、probe 14 = `quirky-funny-fermi`。これらは **すべて別々の Cowork chat session** で実行されたため、codename が異なるのは Cowork の通常挙動（chat ごとに新規 VM が割り当てられる）。

→ §2.11 cross-chat DATA isolation 検証では **同一の codename 期待値ではなく「chat ごとに別 VM が立つこと」自体が前提**になる。probe 18 で「同一 chat 内では codename が安定するか」「別 chat では codename が変わるか」を直接確認する。

### 新発見 2: `CLAUDE_CODE_ENTRYPOINT` UNSET on Cowork Bash tool

CLI baseline（probe 01）では `CLAUDE_CODE_ENTRYPOINT=cli` が Bash tool subprocess に伝わる。Cowork では **UNSET**。

→ research §1.1 表に追記すべき差分：

```diff
| `CLAUDE_CODE_ENTRYPOINT/EXECPATH` 等 `CLAUDE_CODE_*` | ✅ | ✅ | ✅ |
+ ※ CLI のみ。Cowork では Bash tool（`mcp__workspace__bash`）の subprocess には UNSET。
```

これは plugin 作者にとって地味に重要 — env で実行環境（CLI vs Cowork）を分岐する手段が **`CLAUDE_CODE_ENTRYPOINT` の有無**で簡易判別できる可能性。Cowork は env で自身を識別するための marker を一切露出していないので、`CLAUDE_CODE_ENTRYPOINT` の有無が事実上の唯一手がかり。

## probe 14-cowork-parser（Cowork）— DOC-ALIGNED（§2.6 部分的緩和）

実行時の codename: 別 Cowork chat（独立 session）。`verifier-cowork-parser-tests.zip`（hooks.json を stdout-only parser test 配列に差し替えた専用 zip）を新規 chat に upload + enable し、最初の prompt で「initial context 内の `PARSER_TEST_*` を全列挙して」と Claude に質問。

### 投入セット vs 観測結果

| # | 投入した hook command | 観測 marker | 研究 §2.6 (v2.1.119) | v2.1.146-148 結果 |
|---|---|---|---|---|
| 1 | `echo PARSER_TEST_BARE` (SessionStart) | ✅ | OK | 一致 |
| 2 | `bash -c "echo PARSER_TEST_DQ"` | ✅ | OK | 一致 |
| 3a | `bash -c "echo PARSER_TEST_SEMI; echo PARSER_TEST_SEMI_X"` → SEMI | ✅ | OK | 一致 |
| 3b | 同上 → SEMI_X | ✅ | OK | 一致 |
| 4 | `bash -c "echo PARSER_TEST_PIPE \| cat"` | ✅ | OK | 一致 |
| 5 | `bash -c "x=foo; echo PARSER_TEST_VAR_$x"` | ✅（`VAR_` のみ） | OK | 一致（`$x` は外側 `/bin/sh` で空展開、CLI でも同様 — §1.3 既知挙動） |
| 6 | `bash -c "true && echo PARSER_TEST_AND"` | ✅ | **❌ outer parser 分断** | **❗ 不一致（DOC-ALIGNED）** |
| 7 | `bash -c "false \|\| echo PARSER_TEST_OR"` | ✅ | **❌ outer parser 分断** | **❗ 不一致（DOC-ALIGNED）** |
| 8 | `printf PARSER_TEST_PRINTF\n` | ❌ | ❌（whitelist 外） | 一致 |
| UPS-1 | `echo PARSER_TEST_UPS_BARE` (UserPromptSubmit) | ✅ | ✅ context 注入 | 一致 |
| UPS-2 | `bash -c "echo PARSER_TEST_UPS_DQ"` (UserPromptSubmit) | ✅ | ✅ context 注入 | 一致 |

### 結論：v2.1.146-148 で Cowork hook command parser が部分的に緩和

研究 §2.6（v2.1.119 観測）では `bash -c "true && echo ..."` `bash -c "false || echo ..."` は outer parser で**分断され実行されない**とされていた。v2.1.146-148 ではこの 2 構文が**正常に実行されるようになっている**。Plugin 作者にとって以前の落とし穴の 1 つが解消されたことになる。

ただし whitelist 自体は依然存在：`printf` builtin は echo/bash 以外なので reject された（§2.6 の主旨は維持）。

### §2.6 改訂提案

```diff
- AND (`bash -c "true && echo ..."`)             | ✅ | ❌ outer parser 分断 |
- OR  (`bash -c "false || echo ..."`)            | ✅ | ❌ outer parser 分断 |
+ AND (`bash -c "true && echo ..."`)             | ✅ | ✅ v2.1.146-148 で実行成功（v2.1.119 比で緩和）|
+ OR  (`bash -c "false || echo ..."`)            | ✅ | ✅ v2.1.146-148 で実行成功（v2.1.119 比で緩和）|
  printf / cat / sh -c                            | ✅ | ❌ whitelist 外（維持）|
```

### 副次確認: UserPromptSubmit hook の stdout 注入

probe 14 で `UserPromptSubmit` 配列に 2 entry 仕込んだところ、両方とも Claude の context に注入された（最初のプロンプト時点で Claude が UPS marker を認識）。これは §2.5 row「`UserPromptSubmit` (inline echo) → Cowork ✅ context injection」を v2.1.146-148 でも維持していることの再確認。

### Cowork hook parser のテスト戦略（将来の plugin 作者向け）

- `&&` `||` が動くようになったので bash -c 内で複数コマンド連結のパターンが書きやすくなった
- ただし `printf` `cat` `sh -c` 等 echo/bash 以外の builtin / 外部コマンドは依然 outer parser で reject される
- 配布前に **Cowork 実機で hooks の echo 出力を Claude 経由で確認する** のが事実上唯一の検証手段（CLI の `claude plugin validate` では検知不能）

## probe 15-cowork-file-io（Cowork）— PASS（§2.7 確認）

新規 Cowork chat で `/verifier:15-cowork-file-io` を起動。

### 観測

```
[15-BODY 2026-05-22T02:26:13+00:00] tag=alive-check
[15-BODY] file-io-canary files in /tmp:
ls: cannot access '/tmp/file-io-canary-*.txt': No such file or directory
=== Full probe.log === (skill body の 15-BODY 行のみ。15-FM-hook 行は無し)
=== find /tmp -name 'file-io-canary-*' === (該当なし)
Hook did NOT write to probe.log (no 15-FM-hook line found)
Canary file MISSING from /tmp — hook file writes did NOT reach sandbox
```

### subclaim 別 verdict

| subclaim | 観測 | verdict |
|---|---|---|
| (a) hook の inline echo が Claude context に届く | probe 14 で SessionStart / UserPromptSubmit について確認済（PreToolUse も probe 13 で間接確認） | PASS（間接） |
| (b) hook が `/tmp/...` に書いた file が bash sandbox から見えない | `ls /tmp/file-io-canary-*.txt` で `No such file or directory` | PASS |
| (c) hook が `${CLAUDE_PLUGIN_DATA}` に書いた file が bash sandbox から見えない | hook の log line `15-FM-hook` が probe.log に追記されていない | PASS |
| (d) 不可視時のエラー形態 | `ls: cannot access ...: No such file or directory`（silent ではなく明示的なエラー）| 観察 |

### 結論

§2.7 の主張「Cowork で hook 内の file 副作用は届かない」が v2.1.146-148 でも維持されている。**hook と Bash tool の bash sandbox は完全に別の filesystem namespace に分離**されており、両者が同じ `/tmp` パスを使っても **物理的に別の `/tmp` を見ている**（hook 側で書いても bash 側は空、bash 側で書いても hook 側は読めない）。

### Plugin 作者向け takeaway

- Cowork で `${CLAUDE_PLUGIN_DATA}` への永続化に依存する設計は機能しない（read 不可）
- hook で state を持ちたい場合は **stdout 経由で additionalContext として model に injection** する以外の手段が無い（つまり「持続的な state」は実現不能、毎回 hook が echo で context に乗せ直す形しか取れない）
- bash sandbox から `ls` が `No such file or directory` を返すので、**「書いてはいるが reader が見えない」のではなく「書込側か reader 側のどちらかで失敗している」と plugin 開発者には認知される**（silent ではない、診断はしやすい）
