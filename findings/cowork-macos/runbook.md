# Mac Cowork 検証 runbook

`findings/cowork-macos/report.md` の §3 マトリクスの 🔬（要Mac観測）を埋めるための実行手順.
**ユーザが Mac の Claude Desktop / Cowork で各 probe を起動 → 出力を一字一句この repo に貼る → CLI 側 Claude が report を更新** という分業.

## 共通手順

1. probe を Mac Cowork に install（既に inline/zip で入っているなら再 install 不要. GUI marketplace 経路も検証したいなら別途）.
2. **新規 Cowork chat** を開く（SessionStart hook 系は session 開始時に発火するので、chat 冒頭 context に既に marker 行が入る）.
3. 下記 slash command を 1 つずつ起動.
4. **context に注入された marker 行を、skip / 改変せず一字一句コピー**してこの repo の担当者（CLI 側 Claude）に渡す. 行が「無い」場合は「無し」と明記（無いこと自体が観測）.
5. 余裕があれば Claude Desktop の **Export Session** → zip 内 `<sessionId>.jsonl` の hook attachment（`command`/`stdout`/`stderr`/`exitCode`）も添える（context に surface しない hook の真の出力が取れる. team-report §2.2bis）.

判定の軸は各 probe ごとに「**Mac で通常シェルとして展開されるか / Cowork 共通制約が残るか**」.

---

## P1. `cowork-mp-disambig-probe:show-mp-disambig` 【最優先】

```
/cowork-mp-disambig-probe:show-mp-disambig
```

12 行（`MP_DA_*`）が出るはず. 見たい point と Mac 仮説 vs Windows 既知:

| 観測点 | command | Mac 仮説（通常シェル） | Windows 既知 |
|---|---|---|---|
| `MP_DA_CONTROL` | static echo | `static_marker_no_var` | 同左 |
| `MP_DA_DQ` | `echo MP_DA_DQ="double-quoted"` | `double-quoted`（quote 消費） | `"double-quoted"` literal |
| `MP_DA_DQ_INNER` | `hello-"middle"-world` | `hello-middle-world` | literal |
| `MP_DA_HOME` | `echo ...=$HOME` | **`/Users/...`（実値）** | `$HOME` literal |
| `MP_DA_HOME_BRACE` | `${HOME}` | 実値 | literal |
| `MP_DA_PATH` | `$PATH` | 実 PATH | literal |
| `MP_DA_NUL` | `$NO_SUCH_VAR_EXPECT_EMPTY` | **empty**（`MP_DA_NUL=`） | literal |
| `MP_DA_BASH_HOME` | `bash -c 'echo $HOME'` | `/Users/...` | `/home/...`(WSL2) |
| `MP_DA_BASH_HOST` | `bash -c hostname` | Mac 名 or `claude`? | WSL2=Win名 |
| `MP_DA_BASH_PATH` | `bash -c '$PATH'` | macOS PATH（`/usr/lib/wsl/lib` 無し） | WSL2 PATH |
| `MP_DA_BASH_WSL_LIB` | `/usr/lib/wsl/lib` 有無 | **absent** | present |
| `MP_DA_BASH_MNT_C` | `/mnt/c` 有無 | **absent** | present |

**判定**: top-level の `MP_DA_HOME`/`MP_DA_PATH` が実値 + `MP_DA_NUL` が empty + `MP_DA_DQ` が quote 消費 →
「Mac の hook は top-level でも通常シェル parse する」が **多点で確定**（mp-script の ECHO_BARE 単点を補強）.
`WSL_LIB`/`MNT_C` が absent → WSL2 中間層が無いことの裏取り.

---

## P2. `cowork-env-probe:env-check`

```
/cowork-env-probe:env-check
```

- plugin-level SessionStart: `[PLUGIN-HOOK SessionStart] ROOT=[..] DATA=[..] PROJECT=[..] OPT_HELLO=[..] ENTRY=[..] HOST=[..]`
  - **Mac 仮説**: ROOT/DATA/PROJECT すべて実値. HOST=Mac 名. （Windows は全部空）.
  - `OPT_HELLO`（userConfig）が来るかは §7 と連動.
- plugin-level PreToolUse（`Bash|mcp__workspace__bash` matcher）: Bash tool 実行時に surface するか.
  - **Mac 仮説**: Cowork の bash tool 名は `mcp__workspace__bash` なので matcher は当たるはず（§6 の確認も兼ねる）.
- frontmatter hook（skill 側に定義があれば）: **Mac で発火 / surface するか**.
  - **Windows**: 不発（team-report §2.9）. Mac で出れば大きな差分.

**判定**: env の実値化 = §1 DIVERGES の裏取り. frontmatter surface 有無 = §5 と連動.

---

## P3. `cowork-fs-probe:fs-check` 【§4 の核】

```
/cowork-fs-probe:fs-check
```

SessionStart hook が `/tmp/cowork-fs-canary.txt` を書き、skill body の Bash tool が `cat` する.

- **Mac 仮説 A（分割残る）**: hook host = Mac 名, Bash tool host = `claude`(VM), `cat` 失敗（別 namespace）.
  → filesystem 分割は OS 非依存の Cowork アーキ由来、と確定（§4 SAME）.
- **Mac 仮説 B（分割無し）**: hook も Bash tool も同じ host で `cat` 成功 → §4 も Mac では DIVERGES（VM 分離が無い）.

**判定**: `cat` の成否 + 両者の `hostname` を必ず記録. ここが Mac のアーキ仮説（2 層 / VM 分離の有無）を最終決定する.

---

## P4. `cowork-envfile-probe:envfile-check`

```
/cowork-envfile-probe:envfile-check
```

SessionStart hook が `$CLAUDE_ENV_FILE` に `export ENVFILE_MARKER=...` を書き、skill body の Bash tool で読めるか.

- **Mac 仮説**: env が来る Mac では `CLAUDE_ENV_FILE` も set されている可能性 → ただし書き先(host)と Bash tool(VM) が別 namespace なら、§4 が「分割残る」だと **CLAUDE_ENV_FILE が set でも Bash tool に届かない**.
- 観測項目: hook output 内の `CLAUDE_ENV_FILE=[...]` が空か実パスか / body の `$ENVFILE_MARKER`.

**判定**: `CLAUDE_ENV_FILE` 自体の set 有無（Windows は空）+ marker が body に届くか.

---

## P5. block 系（§5）

### P5a. `cowork-blockmethods-probe:block-methods`

```
/cowork-blockmethods-probe:block-methods
```

plugin-level PreToolUse の 3 方式（`decision:block` / `permissionDecision:deny` / `exit 2`）+ control を inline で.
- **Mac 仮説**: Windows と同じく 3 方式とも block, control だけ通る（§5 SAME の見込み）.

### P5b. 外部 script 経由 block（Mac 固有の検証ポイント）

Windows では `${CLAUDE_PLUGIN_ROOT}/hooks/block.sh` が **env 空で exec 失敗 → block 出ない**（team-report §2.10 旧誤りの真因）.
Mac では mp-script で marker.sh が起動できた以上、**外部 script block も起動できる可能性が高い**.
→ 既存 probe に外部 script block の variant が無ければ、`cowork-mp-script-probe` の marker.sh 起動成功
（report §1 観測点 4,5）を根拠に「Mac では外部 script block も動く見込み」と暫定記録. 専用 probe を足すなら別途.

### P5c. `cowork-block-probe`（frontmatter PreToolUse:Skill block）

```
/cowork-block-probe:guard
（その後、自然言語で）victim skill を起動して
```

- **Windows**: block されず victim 実行（frontmatter hook 不発）.
- **Mac 仮説**: frontmatter hook が Mac で発火するなら block される（P2 の frontmatter surface 結果と整合させる）.

---

## P6. `cowork-surface-probe:surface-check`（redirect footgun, §4 の罠）

```
/cowork-surface-probe:surface-check
```

5 variant（単一 echo / 複数文 / if-else / redirect 実行 / redirect 不実行）のうち、
**Windows では redirect トークンを含む V4/V5 が hook 全体 surface しなくなる**.
- **Mac 仮説**: 不明（host loop 実装が OS で違う可能性）. V1〜V5 のどれが surface したかを全部記録.

---

## P7. `cowork-userconfig-probe:uc-check`（§7）

```
/cowork-userconfig-probe:uc-check
```

`opt_plain`/`req_plain`/`opt_secret`/`req_secret` の 4 userConfig + control.
- install / enable 時に **入力 UI が出るか**（Windows: 一切出ない）.
- 値 unset 時の plugin-level hook entry が **silent skip するか**（Windows: skip）.
- skill body の `${user_config.KEY}` 置換（非機密=literal / 機密=block 文字列）.
- **Mac 固有の注目点**: env が来る Mac で、settings.json に値を入れたら `CLAUDE_PLUGIN_OPTION_*` が hook env に届くか
  （UI が無くても settings.json 直編集で値を入れられれば、Mac では機能する可能性）.

---

## P8. §2 裏取り（mp-script と整合確認, 優先度低）

```
/cowork-presub-probe:show-presub
/cowork-expansion-probe:show-expansion
```

- `show-presub`: `PRESUB_TOP_BARE` が実値（Mac）/ literal（Win）, `PRESUB_TOP_SQ` literal, `PRESUB_DATA` 実値（Mac）, `PRESUB_BASH_BRACE` 実値.
- `show-expansion`: `EXP_TOP_DOLLAR`/`EXP_TOP_BRACE` が実 PATH（Mac）/ literal（Win）, `EXP_BRACKET_*` で `/bin/sh` が `[[` 対応か（Mac の `/bin/sh` は dash でなく別実装の可能性 → `EXP_BRACKET_TRUE` が出るかも = Windows と差が出るポイント）.

---

## P9.（任意）skill body 置換値（§3）

verifier plugin を入れているなら:

```
/verifier:16-cowork-path-forms
/verifier:07-skill-body-subst
```

- `BODY_SUBST` 系の `${CLAUDE_PLUGIN_ROOT}` が **macOS host path**（`/Users/<user>/Library/Application Support/Claude/...`）に
  置換されるか. それを Bash tool に渡すと失敗するか（VM 分離次第）, Read tool では読めるか.

---

## 記録の宛先

- 各 probe の生出力 → このファイルの末尾か、`findings/cowork-macos/observations.md`（新規）に貼る.
- 確定したら `findings/cowork-macos/report.md` §3 マトリクスの 🔬 を ✅(SAME) / ❌(DIVERGES) に更新.
