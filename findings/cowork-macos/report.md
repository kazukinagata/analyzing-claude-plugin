# Mac Cowork 独立検証レポート

> このレポートは **macOS の Claude Desktop / Cowork** 単体の挙動を、既存の
> `docs/team-report.md`・`findings/v2.1.*`（いずれも **Windows + WSL2** ホスト固有）
> および記事 `tech-blog-generator/articles/2bc58c12090f72.md`（「…Claude Code Plugin の落とし穴（Cowork 編）」）
> とは **独立に** 記録するもの. 既存知見を前提にせず、Mac で実観測した事実だけを根拠にする.
>
> 検証日: 2026-05-29 / ホスト: macOS (`<mac-host>.local`) / Claude Desktop Cowork
> 観測者: CLI 側 Claude (この repo 内) が、ユーザが Mac Cowork で実行した probe 出力を受け取って記録.

---

## 0. 背景と問題意識

記事 / team-report の Cowork 章はすべて **「Windows ホスト + WSL2 Ubuntu がインストール済みの 1 台」** での観測に基づく.
team-report 冒頭の「検証環境の前提」自身が、`/usr/lib/wsl/lib` を含む PATH・`HOME=/home/<user>`・`hostname=Windows名`
といった具体値は **このマシン固有で一般化不可** と明記している. しかし記事側（公開記事）は、

- §「環境変数の伝播は Cowork で大幅に欠落する」→ `CLAUDE_PLUGIN_*` が **完全に消える**
- §「hook command の `${VAR}` は Cowork で二重に壊れる」→ top-level で `$` 展開が抑止される + env が空

を **「Cowork」一般の性質** として提示している. 本検証の出発点は、Mac Cowork で
`cowork-mp-script-probe:show-mp-script` を 1 回走らせた出力が、これらの中核主張と **真っ向から矛盾した** こと.

---

## 1. 確定した一次観測（`cowork-mp-script-probe:show-mp-script`, Mac Cowork, SessionStart hook）

ユーザが Mac Cowork で受け取った SessionStart hook output（一字一句）:

```
MP_SCRIPT_CONTROL=static_marker_no_var
MP_SCRIPT_ECHO_SQ=${CLAUDE_PLUGIN_ROOT}
MP_SCRIPT_ECHO_BARE=/var/folders/ph/w5mkk5d94cb_jjvzcv_g9pdc0000gn/T/claude-hostloop-plugins/66135c2b7384a210
MP_SCRIPT_MARKER form=bashbrace reached=yes argv0=[/var/folders/ph/.../T/claude-hostloop-plugins/66135c2b7384a210/hooks/marker.sh] ROOT_ENV=[/var/folders/ph/.../66135c2b7384a210] DATA_ENV=[/var/folders/ph/.../a8730419d9c8ad74/plugins/data/cowork-mp-script-probe-inline] HOST=[<mac-host>.local]
MP_SCRIPT_MARKER form=topbare  reached=yes argv0=[/var/folders/ph/.../T/claude-hostloop-plugins/66135c2b7384a210/hooks/marker.sh] ROOT_ENV=[/var/folders/ph/.../66135c2b7384a210] DATA_ENV=[/var/folders/ph/.../a8730419d9c8ad74/plugins/data/cowork-mp-script-probe-inline] HOST=[<mac-host>.local]
```

対応する hooks.json（`cowork-mp-script-probe/hooks/hooks.json`、5 entry の plugin-level SessionStart）と突き合わせた verdict:

| 観測点 | hooks.json の command | Mac Cowork の結果 | 同一 probe の **Windows** 結果（team-report §2.2 追検証） |
|---|---|---|---|
| CONTROL | `echo MP_SCRIPT_CONTROL=static_marker_no_var` | 出る | 出る |
| ECHO_SQ | `echo 'MP_SCRIPT_ECHO_SQ=${CLAUDE_PLUGIN_ROOT}'` | **literal** `${CLAUDE_PLUGIN_ROOT}` | literal |
| ECHO_BARE | `echo MP_SCRIPT_ECHO_BARE=${CLAUDE_PLUGIN_ROOT}` | **実パスに展開** `/var/folders/.../66135c2b7384a210` | **literal `${CLAUDE_PLUGIN_ROOT}`** |
| MARKER topbare | `"${CLAUDE_PLUGIN_ROOT}/hooks/marker.sh" topbare` | **reached=yes**（script 起動成功、argv0 = 実パス） | **行が出ない**（exec 失敗 exit 127） |
| MARKER bashbrace | `bash -c '"$CLAUDE_PLUGIN_ROOT/hooks/marker.sh" bashbrace'` | **reached=yes** | **行が出ない**（env 空で exec 失敗） |
| marker 内 `ROOT_ENV` | `$CLAUDE_PLUGIN_ROOT`（script の env） | **実パス**（env に set されている） | 空 |
| marker 内 `DATA_ENV` | `$CLAUDE_PLUGIN_DATA`（script の env） | **実パス** `.../plugins/data/cowork-mp-script-probe-inline` | 空 |
| marker 内 `HOST` | `$(hostname)` | `<mac-host>.local`（macOS 本体名） | `LAPTOP-BKGB6100`（Windows 名 / WSL2） |

### この 1 出力だけで確定する事実

1. **`CLAUDE_PLUGIN_ROOT` env は Mac Cowork の plugin-level hook に SET されている**
   （`ROOT_ENV` が marker.sh の env から実パスで取れている. ECHO_BARE も同じ実パス）.
   → 記事 §「環境変数の伝播は Cowork で大幅に欠落」/ team-report §2.1「`CLAUDE_PLUGIN_*` が UNSET」は **Mac では成立しない**.

2. **`CLAUDE_PLUGIN_DATA` env も SET されている**（`DATA_ENV` が実パス）.
   → 同上, Mac では `DATA` も来る.

3. **top-level command の `$VAR` 展開は抑止されていない**（ECHO_BARE が実パス）.
   → 記事 §「top-level command では `$VAR` の展開が抑止される」/ team-report §2.2「top-level の `$` 抑止」「shell parse 不在」は **Mac では成立しない**.

4. **single-quote は正しく展開を抑止する**（ECHO_SQ が literal）かつ **事前置換も走っていない**
   （pre-sub なら quote 非依存で実パスになるはず. literal で残った）.
   → これは **通常の POSIX シェルの正しい挙動**で、CLI と同一.

5. **top-level でも `bash -c` でも `${CLAUDE_PLUGIN_ROOT}/hooks/marker.sh` の直接起動が成功する**
   （両 form とも reached=yes, argv0 = 実パス）.
   → 記事 §「hook script を `${CLAUDE_PLUGIN_ROOT}` 経由で起動する典型構成は入口のパス解決で崩れる」は **Mac では崩れない**.

6. **hook は macOS 本体上で動く**（HOST = Mac 名, パスは `/var/folders/.../T/claude-hostloop-plugins/...` = macOS の temp）.
   → WSL2 の中間層は無い. hostname も `claude`(VM) ではなく macOS 本体名.

### 一言で

> **Mac Cowork の plugin-level hook は、フルの `CLAUDE_PLUGIN_*` env を持った通常の macOS ホストシェルで動き、
> 変数展開・script 起動とも CLI と同等に機能する.** 記事 / team-report が「Cowork の構造的欠陥」として
> 提示した中核 2 点（env strip と `$` 抑止）は、**Windows + WSL2 ホスト固有のアーティファクト**であり、
> Mac では再現しない.

---

## 2. Mac Cowork のアーキテクチャ仮説（要追試）

一次観測から導かれる Mac のモデル. Windows の **3 層**（Windows ホスト → WSL2 → host-adjacent VM）に対し、Mac は **2 層** と推定:

```
┌──────────────────────────────────────────────────────────┐
│ ① macOS ホスト (<mac-host>.local)               │
│    Claude Desktop = macOS ネイティブ process              │
│    plugin-level hook を "host loop" で **ネイティブ macOS  │
│    シェル**にそのまま実行（/var/folders/.../              │
│    claude-hostloop-plugins/<hash>/ に plugin を staging）  │
│    → env に CLAUDE_PLUGIN_ROOT / DATA が SET されたまま     │
│      ($ 展開も正常. WSL2 のような env strip 層が無い)      │
│                          │                                │
│                          │ host-adjacent VM mount         │
│                          ↓                                │
│  ┌────────────────────────────────────────────┐          │
│  │ ② host-adjacent Cowork VM                   │          │
│  │   hostname=claude (要確認)                  │ ← Bash    │
│  │   Bash tool (mcp__workspace__bash) を実行   │   tool    │
│  └────────────────────────────────────────────┘          │
└──────────────────────────────────────────────────────────┘
```

含意（**全て probe で確定済み**）:

- WSL2 という中間層が無いぶん、Windows で WSL2 が引き起こしていた「env strip」「top-level `$` 抑止 /
  shell parse 不在」は Mac では起きない（§1/§2 で確定. mp-script + disambig）.
- **hook(ホスト=macOS) と Bash tool(VM=`claude`) が別 filesystem namespace** という分割は Mac でも残る
  （fs-probe で確定: hook が書いた `/tmp` を Bash tool は読めない）. これは OS 非依存の Cowork アーキ由来.
- `mcp__workspace__bash` という tool 名・VM 側機構も Mac で同じ（blockmethods で確定）.
- frontmatter hook は Mac で **発火し block 決定も honor される**（fm-bashblock で直接証明）. ※ `PreToolUse` hook の stdout がそもそも context に出ないのは **Claude Code の公式仕様（全 OS / CLI 共通**。context に入るのは SessionStart / UserPromptSubmit / UserPromptExpansion のみ）なので、発火は echo ではなく block で判定する.

> ⚠ caveat: 観測された data dir は `cowork-mp-script-probe-inline`（`-inline` 接尾辞）で、
> **inline / zip 経路の install** の可能性が高い（team-report §2.6: inline install の data dir 命名）.
> GUI marketplace 経路と install path が一致するかは Mac では未確認（Windows では一致した）.

---

## 3. 記事 7 章 × Mac 検証マトリクス（最終・全項目確定）

記事の 7 つの落とし穴 + 大前提について、Mac 実機で全項目確定. **状態の凡例**:
`✅ SAME` = Windows と同じ（OS 非依存）/ `❌ DIVERGES` = Windows と違う（Win+WSL2 固有のアーティファクト）.

| # | 記事の章（主張） | Windows での結論 | **Mac の状態** | 検証 probe |
|---|---|---|---|---|
| 前提 | Cowork は host/VM の 2 段、hook は host 側 | host=WSL2(3層), hostname=Win名 | **❌ DIVERGES（確定）**: hook=macOS ネイティブ host(2層, hostname=Mac名), Bash tool=VM(`claude`) | mp-script ✅ / env-probe ✅ |
| §1 | 環境変数の伝播が大幅欠落（`CLAUDE_PLUGIN_*` 消失） | UNSET | **❌ DIVERGES（確定）**: plugin-level hook は ROOT/DATA/PROJECT 実値, `ENTRY=local-agent`. body(Bash tool)は CLI 同様 unset | mp-script ✅ / env-probe ✅ |
| §5前提 | frontmatter hook は Cowork で発火しない | 不発（block も効かない） | **❌ DIVERGES（直接証明・確定）**: frontmatter hook は **発火し block も honor**（fresh session / resume で失効）. ※ echo が見えないのは `PreToolUse` stdout が context に行かない**公式仕様**（全OS共通）ゆえで、発火は block で判定. fm-bashblock probe で実証 | env-probe ✅ / block-probe ✅ / **fm-bashblock ✅** |
| §2 | hook の `${VAR}` が二重に壊れる（top-level `$`抑止 + env空） | literal + 空 | **❌ DIVERGES（多点確定）**: top-level で `$HOME`/`$PATH`/unset/quote すべて通常 shell parse + env 展開, script 起動成功 | mp-script ✅ / disambig ✅ / presub 🔬 / expansion 🔬 |
| §3 | skill body の `${CLAUDE_PLUGIN_ROOT}` がホストパスに化ける | Windows path 埋め込み(Bash不可/Read可) | **✅ SAME（構造）/ 形式のみ DIVERGES**: macOS host path（`/var/folders/.../claude-hostloop-plugins/<hash>`）に事前置換. VM Bash 不可・Read tool 可も同じ. 違いはパス形式だけ | bodypath ✅ |
| §4 | hook と Bash tool の filesystem は完全に別 | 別 namespace, `CLAUDE_ENV_FILE` も空, redirect footgun あり | **✅ SAME（filesystem分割）/❌ DIVERGES（細部）**: 分割は確定. `CLAUDE_ENV_FILE` は **Mac では set**（Win空）だが VM 分離で届かず結果同. **redirect footgun は Mac で起きない**（V4/V5 も surface, Win 固有） | fs-probe ✅ / envfile ✅ / surface ✅ |
| §5 | PreToolUse block（plugin-level可/外部script・redirectで silent fail / frontmatter不可） | inline のみ可 | **plugin-level 3方式=✅SAME / frontmatter=❌DIVERGES**: plugin-level decision/permission/exit2 すべてブロック. **frontmatter PreToolUse:Skill/Bash block は Mac の fresh session で効く（Win は不発）/ resume で失効**. redirect footgun は Mac で無い（surface 確認済）ので外部script・redirect 起因の silent fail も Mac には無い | blockmethods ✅ / block-probe ✅ / fm-bashblock ✅ / surface ✅ |
| §6 | Bash tool 名が `mcp__workspace__bash` | MCP 経由名 | **✅ SAME（確定）**: matcher `Bash\|mcp__workspace__bash` が Cowork bash tool に命中（block 成立で実証） | blockmethods ✅ |
| §7 | userConfig 入力 UI が Cowork に無い | 入力経路ゼロ, hook entry silent skip | **✅ SAME（確定）**: 入力 UI 無し / unset entry は silent skip / body は非機密=literal・機密=block 文字列. UI 不在は OS 非依存の Cowork 共通制約. （settings.json 手動注入の可否のみ未検証・優先度低） | userconfig-probe ✅ |

### 「env が空だったことが原因」だった Windows 結論の波及（Mac では崩れる）

§1/§2 が Mac で覆ったことで、Windows の「env が空だったことが原因」の結論は Mac では成立しない:

- team-report §2.1「hook から plugin install dir を取る手段はほぼ消失」→ Mac では `$CLAUDE_PLUGIN_ROOT` で取れる（mp-script で実証）.
- team-report §2.10 の旧誤りの真因「`${CLAUDE_PLUGIN_ROOT}/hooks/block.sh` が env 空で exec 失敗 → block 出ない」
  → Mac では marker.sh が env 付きで起動できた（OBS-1）ので、**外部 script 経由の block も Mac では機能する**（その失敗原因が Mac には無い）.
- 記事 §3 の「hook 側で `find /sessions` で localize せよ」という回避策 → Mac の **hook** では不要（`$CLAUDE_PLUGIN_ROOT` がそのまま使える）.
  ただし **Bash tool(VM) 側**で host path が使えない問題は §3/§4 のとおり Mac でも残るので、Bash tool から bundle 物を動かす用途では
  localize（または Read tool 経由）が引き続き必要.

---

## 4. 検証の実施状況（全 probe 完了）

記事 7 章 + 大前提について、Mac Cowork 実機で全 probe を実行済み（生ログは `observations.md` OBS-1〜11）.
手順は `findings/cowork-macos/runbook.md`.

| OBS | probe | 確定した記事章 |
|---|---|---|
| 1 | cowork-mp-script-probe | 前提 / §1 / §2 |
| 2 | cowork-mp-disambig-probe | §2（多点） |
| 3 | cowork-env-probe | §1 / 3 tier / ENTRY=local-agent |
| 4 | cowork-fs-probe | §4 filesystem 分割 |
| 5 | cowork-envfile-probe | §4 CLAUDE_ENV_FILE |
| 6 | cowork-blockmethods-probe | §5 plugin-level block / §6 tool 名 |
| 7,7b | cowork-block-probe | §5 frontmatter block（fresh 効く/resume 失効） |
| 8 | **cowork-fm-bashblock-probe**（新規 b2f714c 前） | frontmatter 発火の直接証明 |
| 9 | cowork-surface-probe | §4 redirect footgun |
| 10 | cowork-userconfig-probe | §7 |
| 11 | **cowork-bodypath-probe**（新規 b2f714c） | §3 skill body 置換 |

未実施（任意・優先度低）: `cowork-presub`/`cowork-expansion`（§2 の裏取り. disambig で多点確定済みのため冗長）/
userConfig を settings.json 手動注入したとき Mac の hook env に届くか.

未実施（新規・要実機）: **`cowork-data-persist-probe`** — `$CLAUDE_PLUGIN_DATA` に永続化した値が
**Cowork の chat session を跨いで残るか**（§2.11 DATA isolation の Mac 版）. OBS-1/3/11 で DATA の
**パス値**（host 側 `/var/folders/.../plugins/data/<plugin>-inline`）と **body 置換値** は確定済みだが、
**別 chat を跨いだ永続性は未観測**. write+read-back は VM body では不可（DATA unset）なので SessionStart
hook(host)側の `persist.sh` で実施する設計. 別 chat を 2 回開いて `DP_PRIOR_COUNT` と `DP_DATA_HASH` を比較する.

---

## 5. 確定結論

### 5.1 一行サマリ

> **記事 / team-report が「Cowork の構造的欠陥」として書いた事の多くは、実は Windows+WSL2 ホスト固有の
> アーティファクトだった. Mac Cowork は「① ネイティブ macOS host で動く plugin-level hook（フル env・通常シェル・
> CLI 同等）＋ ② host-adjacent VM(`claude`) で動く Bash tool」の 2 層で、Windows の env strip / `$` 抑止 /
> shell parse 不在 / redirect footgun / frontmatter 完全不発 は、いずれも Mac では起きない.**

### 5.2 Mac で Windows と違う（❌ DIVERGES）

| 項目 | Windows+WSL2 | Mac |
|---|---|---|
| 大前提のアーキ | 3 層（Win→WSL2→VM） | **2 層（macOS host→VM）** |
| §1 hook env | `CLAUDE_PLUGIN_*` 全消失 | **ROOT/DATA/PROJECT 実値, ENTRY=local-agent** |
| §2 top-level `$VAR` | literal（shell parse 不在） | **通常 shell parse + env 展開** |
| §2 hook から install dir 取得 | 不可 | **`$CLAUDE_PLUGIN_ROOT` で可** |
| §4 redirect footgun | あり（`>`/`>>` で hook 消失） | **無い**（V4/V5 も surface） |
| §4 `CLAUDE_ENV_FILE` | 未設定（空） | **set される**（ただし VM 分離で Bash tool には届かない=結果は同じ） |
| §5 frontmatter block | 完全不発 | **fresh session で honor**（PreToolUse:Skill/Bash とも. resume で失効） |
| §3 skill body 置換のパス形式 | `C:/Users/.../Claude/...` | **`/var/folders/.../claude-hostloop-plugins/<hash>`** |

### 5.3 Mac でも Windows と同じ（✅ SAME＝OS 非依存の Cowork アーキ由来）

- **§4 hook(host) と Bash tool(VM=`claude`) の filesystem 分割**（hook が書いた `/tmp` を Bash tool は読めない）.
- **§3 skill body の置換構造**（host path に化ける / VM Bash 不可 / Read tool 可）— 違いはパスの文字列形式だけ.
- **§5 plugin-level PreToolUse block**（decision / permissionDecision / exit2 の 3 方式とも honor）.
- **§6 Bash tool 名 `mcp__workspace__bash`**（matcher 両対応が必要なのは同じ）.
- **§7 userConfig 入力 UI 不在 / unset entry の silent skip / 機密 body block 文字列**.
- **`PreToolUse` hook の stdout は context に渡らない**（発火はする）. これは Cowork 固有ではなく **Claude Code の公式仕様で全 OS / CLI 共通**（context に stdout が入るのは SessionStart / UserPromptSubmit / UserPromptExpansion のみ）.

### 5.4 重要な再解釈（このレポートで判明）

- 「Cowork で frontmatter hook は発火しない」（team-report §2.9）は、Windows の観測では正しいが **Mac には当てはまらない**.
  Mac では **frontmatter hook は発火し block 決定も honor される**（fm-bashblock probe で echo 無し block を直接確認）.
  当初「不発」に見えた真因は、**`PreToolUse` hook の stdout がそもそも context に渡らない公式仕様**
  （[hooks docs](https://code.claude.com/docs/en/hooks): stdout が context に入るのは SessionStart / UserPromptSubmit / UserPromptExpansion のみ。`PreToolUse` は debug log 行き）を取り違え、echo の有無で発火を判定していたこと.
  **発火の有無は echo ではなく block で判定すべき**で、それで見ると Mac=発火 / Windows=不発.
  つまり「echo が context に出ない」（OS 非依存の仕様）と「block が honor される」（OS 依存の事実）を切り分けて初めて正しく読める.
- frontmatter block は **resume を跨ぐと登録が失効**（block-probe で確認）. 長期 guard を frontmatter に置くべきでないのは
  Mac/Win 共通の結論だが、理由が違う（Win=そもそも効かない / Mac=効くが resume で消える）.

### 5.5 記事・team-report への含意

- 記事は挙動を「Cowork 一般」として提示しているが、実態は **ホスト OS（Windows+WSL2 / macOS）で大きく変わる**.
  特に **§1（env 欠落）・§2（`${VAR}` 二重破壊）・redirect footgun・frontmatter 完全不発 は macOS では誤り**.
- 最低限、env / shell expansion / hook 実行層については「Windows+WSL2 の話」と「macOS の話」を**明示的に分けて**記述すべき.
- CLI/Cowork(Mac)/Cowork(Win) を分ける判定子: hook 側で `CLAUDE_CODE_ENTRYPOINT`（CLI=`cli` / Cowork=`local-agent`）、
  `hostname`（CLI/Mac-hook=Mac名 / Win-hook=Win名 / Bash tool=`claude`）.
- ただし **plugin 設計の最終結論（guard は plugin-level inline / userConfig に依存しない / state は永続化しない 等）は
  両 OS で概ね同じ**. 理由が OS で違うだけで、可搬な plugin を書くなら最も厳しい Windows 制約に合わせておけば Mac でも動く.

