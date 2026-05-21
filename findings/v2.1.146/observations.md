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

---

(以降、probe 06-21 を回しながら追記)
