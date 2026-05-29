# Mac Cowork 生観測ログ

probe 出力を一字一句、改変なしで時系列に貼る場所. 解釈は `report.md` 側で行う.

---

## OBS-1 — `cowork-mp-script-probe:show-mp-script`

- 日時: 2026-05-29
- 環境: macOS Claude Desktop / Cowork, host=`<mac-host>.local`
- install 経路: 推定 inline/zip（data dir 接尾辞 `-inline`. GUI marketplace 経路は未確認）
- 取得元: SessionStart:resume hook output（context 注入分）

```
MP_SCRIPT_CONTROL=static_marker_no_var
MP_SCRIPT_ECHO_SQ=${CLAUDE_PLUGIN_ROOT}
MP_SCRIPT_ECHO_BARE=/var/folders/ph/w5mkk5d94cb_jjvzcv_g9pdc0000gn/T/claude-hostloop-plugins/66135c2b7384a210
MP_SCRIPT_MARKER form=bashbrace reached=yes argv0=[/var/folders/ph/w5mkk5d94cb_jjvzcv_g9pdc0000gn/T/claude-hostloop-plugins/66135c2b7384a210/hooks/marker.sh] ROOT_ENV=[/var/folders/ph/w5mkk5d94cb_jjvzcv_g9pdc0000gn/T/claude-hostloop-plugins/66135c2b7384a210] DATA_ENV=[/var/folders/ph/w5mkk5d94cb_jjvzcv_g9pdc0000gn/T/claude-hostloop-plugins/a8730419d9c8ad74/plugins/data/cowork-mp-script-probe-inline] HOST=[<mac-host>.local]
MP_SCRIPT_MARKER form=topbare reached=yes argv0=[/var/folders/ph/w5mkk5d94cb_jjvzcv_g9pdc0000gn/T/claude-hostloop-plugins/66135c2b7384a210/hooks/marker.sh] ROOT_ENV=[/var/folders/ph/w5mkk5d94cb_jjvzcv_g9pdc0000gn/T/claude-hostloop-plugins/66135c2b7384a210] DATA_ENV=[/var/folders/ph/w5mkk5d94cb_jjvzcv_g9pdc0000gn/T/claude-hostloop-plugins/a8730419d9c8ad74/plugins/data/cowork-mp-script-probe-inline] HOST=[<mac-host>.local]
```

補足（ユーザ確認済み）:
- `MP_DA_BASH_HOME` を含む `MP_DA_*` 系の行は startup/resume いずれにも **無し** →
  これは `cowork-mp-disambig-probe` を**まだ Mac で走らせていない**ことを意味するだけ（probe 未実行 = 観測対象外）.
  Mac での disambig は runbook P1 で取得する.

→ 解釈・verdict は `report.md` §1.

---

## OBS-2 — `cowork-mp-disambig-probe:show-mp-disambig`

- 日時: 2026-05-29 / 環境: macOS Claude Desktop / Cowork
- 取得元: SessionStart hook output（全 12 marker surface）

```
MP_DA_CONTROL=static_marker_no_var
MP_DA_DQ=double-quoted
MP_DA_DQ_INNER=hello-middle-world
MP_DA_HOME=/Users/kazukinagata
MP_DA_HOME_BRACE=/Users/kazukinagata
MP_DA_PATH=/Users/kazukinagata/.nvm/versions/node/v24.15.0/bin:/Users/kazukinagata/.local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin
MP_DA_NUL=
MP_DA_BASH_HOME=/Users/kazukinagata
MP_DA_BASH_HOST=<mac-host>.local
MP_DA_BASH_PATH=（top-level PATH と同一）
MP_DA_BASH_WSL_LIB=absent
MP_DA_BASH_MNT_C=absent
```

verdict（全点 surface, exit 0 想定）:
- DQ / DQ_INNER: quote 消費 → **top-level で shell parser が走っている**
- HOME / HOME_BRACE / PATH: 実値展開 → **env 展開あり**
- NUL: `$NO_SUCH_VAR_EXPECT_EMPTY` → **empty**（literal ではない）= shell が unset を空に展開
- BASH_HOST: `<mac-host>.local`（VM の `claude` ではない）= hook は **macOS host 側**
- WSL_LIB / MNT_C: **absent** = WSL2 中間層は無い
- PATH に `/opt/homebrew/bin`・`.nvm/.../v24.15.0/bin` = **ユーザの macOS ログインシェル env をそのまま継承**

→ Windows（HOME/PATH/NUL/DQ すべて literal）と**全点で逆**。Mac は top-level command を
ネイティブ macOS シェルで通常通り実行。team-report §2.2 の「shell parse 不在」モデルは Mac で完全に否定。
これで report §2 は単点(mp-script)から**多点確定**に昇格。

---

## OBS-3 — `cowork-env-probe:env-check`

- 日時: 2026-05-29 / 環境: macOS Claude Desktop / Cowork（startup + resume 複数回）

plugin-level SessionStart hook（ホスト側, 毎回発火）:
```
[PLUGIN-HOOK SessionStart] ROOT=[/var/folders/.../bccbb369fc252947] DATA=[/var/folders/.../cowork-env-probe-inline] PROJECT=[.../outputs] ENTRY=[local-agent] HOST=[<mac-host>.local]
```

skill body の Bash tool（VM 側）:
```
[BODY] ROOT=[(unset)] DATA=[(unset)] PROJECT=[(unset)] ENTRY=[(unset)] HOST=[claude]
```

frontmatter hook（SessionStart / PreToolUse 両 matcher, resume 複数回挟んでも）:
```
[FRONTMATTER-SessionStart] → 無し（未発火 / 未 surface）
[FRONTMATTER-PreToolUse]   → 無し（未発火 / 未 surface）
```

`[PLUGIN-HOOK PreToolUse]`（matcher `Bash|mcp__workspace__bash`）: **今回の報告では明示されず（要再確認）**。
→ §6（Cowork の bash tool 名に matcher が当たるか）と plugin-level PreToolUse の surface 有無は block step で確定する.

verdict:
- **§1 env 伝播**: plugin-level hook は ROOT/DATA/PROJECT すべて実値、`ENTRY=local-agent`。
  → Windows（全部空）と逆。**❌ DIVERGES 確定（mp-script に続き 2 probe 目）**。
- **ENTRY=local-agent**: CLI の `cli` に対し Cowork は `local-agent`。**hook 側での CLI/Cowork 判別子**として使える（hostname 判定の代替）。
- **PROJECT=.../outputs**: Cowork では `CLAUDE_PROJECT_DIR` が outputs ディレクトリを指す。
- **body（Bash tool）**: 全 env unset・`HOST=claude` = VM。CLI の tier-3 と同じく Bash tool は plugin env を持たない。
  さらに hook の `HOST=Mac名` と body の `HOST=claude` が違う → **hook(macOS host)/Bash tool(VM) の 2 層分離は Mac でも存在**（§4 が SAME 寄りである強い傍証。fs-probe で最終確定）。
- **frontmatter hook**: Mac でも発火 / surface しない → **✅ SAME（Windows と同じ, team-report §2.9 / 記事 §5 frontmatter は Mac でも成立）**。

---

## OBS-4 — `cowork-fs-probe:fs-check`

- 日時: 2026-05-29 / 環境: macOS Claude Desktop / Cowork

SessionStart hook（host 側）: `[FS-HOOK] wrote /tmp/cowork-fs-canary.txt on host=<mac-host>.local`

skill body の Bash tool（VM 側）:
```
BODY host=claude
--- cat /tmp/cowork-fs-canary.txt ---
cat: /tmp/cowork-fs-canary.txt: No such file or directory
--- ls ---
ls: cannot access '/tmp/cowork-fs-canary.txt': No such file or directory
```

verdict:
- hook host = `<mac-host>.local`（macOS）/ Bash tool host = `claude`（VM）。
- hook が書いた `/tmp/cowork-fs-canary.txt` を Bash tool から `cat`/`ls` できない（別 filesystem namespace）。
- → **§4「hook と Bash tool は完全に別の filesystem」は Mac でも成立。✅ SAME（確定）**。
  filesystem 分割は OS 非依存の Cowork アーキ（host hook / host-adjacent VM）由来であり、
  Windows の WSL2 とは無関係に Mac でも残る。これで **Mac = 2 層（macOS host hook / VM Bash tool）** が最終確定。
- 注意: §4 のうち `CLAUDE_ENV_FILE` 経路は別途 envfile-probe（OBS-5）で確認。

---

## OBS-5 — `cowork-envfile-probe:envfile-check`

- 日時: 2026-05-29 / 環境: macOS Claude Desktop / Cowork

SessionStart hook output（host 側, context 注入）:
```
[DIAG-ENVFILE] CLAUDE_ENV_FILE=[/var/folders/ph/.../T/claude-hostloop-plugins/c6add37781fbc3b4/session-env/53b52a06-aaa0-4535-b48e-d5f2621f2921/sessionstart-hook-0.sh] host=<mac-host>.local
[DIAG-MULTI] line1 — あり
[DIAG-MULTI] line2 — あり
```

skill body の Bash tool（VM 側）:
```
BODY host=claude
BODY ENVFILE_MARKER=[(unset)]
```

verdict:
- **`CLAUDE_ENV_FILE` は Mac hook env に SET されている**（実パス. session-env/<sid>/sessionstart-hook-0.sh）。
  → Windows（空）と **❌ DIVERGES**（変数の存在）。Mac の hook env は CLI と同様に豊富.
- ただし body の `ENVFILE_MARKER=(unset)` → **env file 機構は Bash tool(VM) に届かない**。
  原因は §4 の filesystem 分割: hook(host) が書いた env file を VM 側が読めない。
- → **実用結果（hook→Bash tool の env 受け渡し不可）は Windows と同じ（SAME）だが、原因が違う**:
  - Windows: `CLAUDE_ENV_FILE` 自体が空（機構が起動すらしない）
  - Mac: `CLAUDE_ENV_FILE` は set・hook は書けるが、**VM 分離で Bash tool に届かない**
- 副産物: `[DIAG-MULTI]` 複数文 echo hook は両行とも surface（redirect 無しなら複数文OK。surface-probe の前哨）。

---

## OBS-6 — `cowork-blockmethods-probe:block-methods`

- 日時: 2026-05-29 / 環境: macOS Claude Desktop / Cowork
- probe: plugin-level PreToolUse, matcher `Bash|mcp__workspace__bash`, inline block ロジック

| # | marker | 方式 | 結果 |
|---|---|---|---|
| 1 | M_DECISION | `decision:block`（レガシー） | **ブロック** `BLK-decision` |
| 2 | M_PERMISSION | `hookSpecificOutput.permissionDecision:deny`（現行標準） | **ブロック** `BLK-permission` |
| 3 | M_EXIT2 | `exit 2` | **ブロック**（hook error） |
| 4 | CONTROL | なし | 実行 `RESULT CONTROL ran host=claude` |

verdict:
- **§5 plugin-level PreToolUse block は Mac でも 3 方式すべて有効。✅ SAME（確定）**。
- ブロックが起きた = **plugin-level PreToolUse hook が Mac Cowork で発火・honor される**
  （STEP 2 / OBS-3 で保留した「plugin-level PreToolUse の発火」もこれで確定）。
- matcher `Bash|mcp__workspace__bash` が当たった = **Cowork の bash tool 名は `mcp__workspace__bash`**。
  → **§6 ✅ SAME（確定）**。tool 名は OS 非依存の Cowork(VM/MCP) 機構由来。
- 注: 本 probe は **inline** block。`${CLAUDE_PLUGIN_ROOT}/hooks/block.sh` 外部 script 経由の block は、
  OBS-1 で marker.sh が起動できた事実（env が set）から **Mac では効く見込み**（Windows は env 空で exec 失敗し
  block 出ずが team-report §2.10 旧誤りの真因. Mac ではその原因が無い）。専用 probe で要最終確認だが論理的に従う。

---

## OBS-7 — `cowork-block-probe`（guard → victim, frontmatter PreToolUse:Skill block）

- 日時: 2026-05-29 / 環境: macOS Claude Desktop / Cowork

| run | session 状態 | victim 起動 | 結果 |
|---|---|---|---|
| 1 | fresh startup（guard arm 直後・同一 turn） | 自然言語 | **`BLOCKED-BY-GUARD-HOOK`** — block honor, victim 走らず |
| 2 | **resume 後** | 自然言語（"victim スキルを実行して"） | `VICTIM-RAN-MARKER ... host=claude` — block 不発, victim 実行 |

verdict（暫定, no-resume コントロール OBS-7b で確定予定）:
- **Mac では frontmatter PreToolUse:Skill block が fresh session 内で honor された（run 1）**。
  → Windows（team-report §2.10: frontmatter block は honor されず victim 実行）と **❌ DIVERGES**。CLI §1.11 と同じ挙動。
- **resume を挟むと block 失効（run 2）**。frontmatter hook 登録が resume を越えて保持されない（Cowork のセッションライフサイクル由来）。
- **STEP 2 / OBS-3 の「frontmatter hook は発火しない」を修正する必要**:
  正しくは「frontmatter hook の **stdout は context に surface しない**（env-probe の echo が出なかった）が、
  **block 決定は fresh session で honor される**（本 probe）」. 発火そのものはしている可能性が高い.
- → no-resume コントロール（OBS-7b）で「resume させずに victim を複数回呼んでも block が持続するか」を確認し、
  「fresh では確実に効く / resume が失効トリガ」を切り分ける.

---

## OBS-7b — `cowork-block-probe`（no-resume コントロール）

- 目的: resume を一切挟まず、fresh session で guard arm → victim を起動して block が成立するか.
- 環境: macOS Claude Desktop / Cowork, 新規 chat

```
/guard → GUARD-ARMED-MARKER host=claude
（続けて自然言語）victim スキルを実行してください
→ Error: BLOCKED-BY-GUARD-HOOK  （victim body は実行されず）
```

verdict（OBS-7 + OBS-7b 合わせて確定）:
- **fresh session（resume なし）では frontmatter PreToolUse:Skill block が成立**（OBS-7 run1 と OBS-7b、別 session で 2 回再現）。
- **resume 後は失効**（OBS-7 run2）。失効トリガは resume。
- → **§5 frontmatter block: Mac は fresh session で効く（CLI §1.11 と同じ）/ resume で失効。Windows（常に不発）とは ❌ DIVERGES**。
- 残る微小な未確定: 「同一 fresh session 内で victim を **2 回目**起動しても block が持続するか」は未取得
  （各 session とも 1 回目で確認）。ただし fresh 2 連続成功 + resume 1 回失敗から、失効トリガは resume と判断。
- **STEP 2/OBS-3 の修正確定**: 「frontmatter hook は Mac でも発火しない」は誤り。正しくは
  **「frontmatter hook の stdout は context に surface しないが、block 決定は fresh session で honor される」**。
  env-probe の `[FRONTMATTER-*]` echo が出なかったのは stdout 非 surface のため（発火していなかったわけではない）。

---

## OBS-8 — `cowork-fm-bashblock-probe:fm-bashblock`（frontmatter 発火の直接証明）

- 日時: 2026-05-29 / 環境: macOS Claude Desktop / Cowork, **fresh chat（resume なし）**
- probe: 新規作成（commit 66efdcc）. frontmatter PreToolUse:Bash hook が **echo せず block JSON のみ**を出す.

| command | 内容 | 結果 |
|---|---|---|
| marked | `echo "... FMBLOCK_MARKER host=$(hostname)"`（マーカー入り） | **ブロック** `FM-BASH-BLOCKED-NO-ECHO`（echo 出力なし） |
| control | `echo "FM-CONTROL ran ... host=$(hostname)"`（マーカー無し） | 実行 `FM-CONTROL ran (should run) host=claude` |

verdict（**確定**）:
- marked がブロック + control が実行 → **frontmatter PreToolUse:Bash hook は Mac Cowork で発火し、block 決定が honor される**。
- hook は echo を一切していない（block JSON のみ）ので、**stdout 非 surface でも制御は効く**ことが直接証明された。
- → **STEP 2 / OBS-3 の再解釈が確定**:
  「frontmatter hook は Mac でも発火する。ただし **(a) stdout は context に surface しない**（env-probe の echo が出ない真因）、
  **(b) block 決定（制御）は fresh session で honor される**」。
  env-probe で `[FRONTMATTER-*]` が見えなかったのは「発火しなかった」のではなく「stdout が注入経路に乗らない」ため.
- Windows（frontmatter hook は stdout も block も効かない＝完全不発, team-report §2.9/§2.10）とは **❌ DIVERGES**。

---

## OBS-9 — `cowork-surface-probe:surface-check`（redirect footgun）

- 日時: 2026-05-29 / 環境: macOS Claude Desktop / Cowork

| variant | hook command の形 | Mac surface | Windows 既知 |
|---|---|---|---|
| V1 | 単一 echo | ✅ `[V1] plain` | ✅ |
| V2 | 複数文 echo | ✅ `[V2] a` / `[V2] b` | ✅ |
| V3 | if/then/else（redirect なし） | ✅ `[V3] x` / `[V3] then`（else は条件偽で非実行・正常） | ✅ |
| V4 | **redirect 実行あり** `>> /tmp/v4probe.txt` | ✅ `[V4] x` / `[V4] after-redirect` | **❌ 消失** |
| V5 | **ガード付き redirect**（`>> "$CLAUDE_ENV_FILE"`） | ✅ `[V5] x` / `[V5] then2`（then 分岐＝`$CLAUDE_ENV_FILE` 非空, OBS-5 と整合） | **❌ 消失** |

verdict（**確定**）:
- **redirect footgun は Mac では起きない**。`>`/`>>` を含む hook command（V4/V5）も stdout が正常に surface。
  → Windows（redirect トークンの存在だけで hook 丸ごと非 surface, team-report §2.8 footgun）とは **❌ DIVERGES**。
  redirect footgun は **Windows host loop 実装固有**のアーティファクトで、Mac の host loop には無い。
- V5 が then2（=`$CLAUDE_ENV_FILE` 非空）→ OBS-5 の「`CLAUDE_ENV_FILE` は Mac で set」を再確認。
- hook host=`<mac-host>.local` / Bash tool host=`claude` も再確認（2層）。

---

## OBS-10 — `cowork-userconfig-probe:uc-check`（§7 userConfig）

- 日時: 2026-05-29 / 環境: macOS Claude Desktop / Cowork

install/enable 時: **入力 UI（フォーム）は出ない**（ユーザ目視）。

plugin-level SessionStart hook（UC-HOOK）:
```
UC-HOOK control=static_marker
（opt_plain / req_plain / opt_secret / req_secret を参照する 4 entry は 1 行も出ない = silent skip）
```

skill body（pre-sub, 全 userConfig unset 状態）:
```
BODY opt_plain=${user_config.opt_plain}                                              （非機密・任意 → literal）
BODY req_plain=${user_config.req_plain}                                              （非機密・必須 → literal）
BODY opt_secret=[sensitive option 'opt_secret' not available in skill content]       （機密・任意 → block 文字列）
BODY req_secret=[sensitive option 'req_secret' not available in skill content]       （機密・必須 → block 文字列）
```

verdict（**確定**）:
- **入力 UI 不在 → ✅ SAME**（Windows と同じ. Cowork 共通制約, OS 非依存）。
- **unset userConfig 参照 hook entry の silent skip → ✅ SAME**。
- **body 置換**: 非機密 unset = literal / 機密 = block 文字列 → ✅ SAME（§1.4 の機密 block は Mac でも有効）。
- **required/optional の区別は runtime に影響しない**（UI が無く値は常に unset）→ SAME。
- → **§7「userConfig 入力 UI が Cowork に存在しない」は Mac でも成立。✅ SAME（確定）**。
- 残る Mac 固有の未確認（任意）: Mac の hook env は豊富なので、**settings.json に値を直接書けば
  `CLAUDE_PLUGIN_OPTION_*` が hook env に届くか**（UI 無しでも手動設定で機能しうるか）は未検証。
  ただし Cowork で settings.json を編集する経路自体が乏しいため優先度低。

---

## OBS-11 — `cowork-bodypath-probe:bodypath`（§3 skill body 置換値）

- 日時: 2026-05-29 / 環境: macOS Claude Desktop / Cowork
- probe: 新規作成（commit b2f714c）

手順1（skill body の事前置換 + VM Bash）:
```
BODY_ROOT=/var/folders/ph/.../T/claude-hostloop-plugins/0af25abfcbf64f24
BODY_DATA=/var/folders/ph/.../T/claude-hostloop-plugins/3ab535bc777efc64/plugins/data/cowork-bodypath-probe-inline
BODY_SKILL_DIR=/var/folders/ph/.../T/claude-hostloop-plugins/0af25abfcbf64f24/skills/bodypath
BODY_HOST=claude
--- VM Bash ---
ls: cannot access '.../0af25abfcbf64f24/assets/marker.txt': No such file or directory
cat: .../assets/marker.txt: No such file or directory
```

手順2（Read tool でホストパスの bundled file を読む）: **成功** — `BODYPATH-MARKER-FILE-CONTENT ...` を読めた。

verdict（**確定**）:
- skill body の `${CLAUDE_PLUGIN_ROOT}` 等は **macOS ホストパス**（`/var/folders/.../claude-hostloop-plugins/<hash>`）に
  事前置換される（hook 側 staging path と同形. Windows は `C:/Users/.../Claude/...`）。
- そのパスは **VM Bash tool（host=claude）から存在せず** `ls`/`cat` 失敗。
- 一方 **Read tool はホスト FS を直接読めるので bundled file を読めた**。
- → **記事 §3「skill body はホストパスに化ける／Bash 不可・Read 可」は Mac でも成立。✅ SAME（構造）**。
  違いは **パスの文字列形式だけ**（macOS `/var/folders` vs Windows `C:/Users`）= **❌ DIVERGES（形式のみ）**。
- 事前置換が env 非依存（quote 非依存の真の pre-sub）である点も CLI/Windows と一致。
```

