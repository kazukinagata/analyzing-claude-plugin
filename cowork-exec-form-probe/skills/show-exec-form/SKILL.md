---
name: show-exec-form
description: Surfaces the EXEC_* marker lines emitted by the plugin-level SessionStart hooks, which run hook commands in EXEC FORM (args present). Used to test whether exec form resolves ${CLAUDE_PLUGIN_ROOT} to a real path and exports it as an env var on Cowork, where shell form (§2.1/§2.2) failed both.
user-invocable: true
---

# show-exec-form

このプラグインの plugin-level SessionStart hook が session 開始時に **7 種類の exec form エントリ**（すべて `args` あり）を実行しています。直前の context（system-reminder / additional context / hook output として注入されたもの）から、以下のプレフィックスで始まる行を**全て一字一句そのまま**貼ってください。プレフィックスが見当たらない場合は「無し」と明記してください。

- `EXEC_CONTROL=` — `{command:"bash", args:["-c","echo EXEC_CONTROL=static_no_var"]}`（exec form が走り surface するかの対照）
- `EXEC_ARGS_PLACEHOLDER=` — `{command:"bash", args:["-c","echo EXEC_ARGS_PLACEHOLDER=[$1]","_","${CLAUDE_PLUGIN_ROOT}"]}`（**launcher のテキスト事前置換**テスト。`${CLAUDE_PLUGIN_ROOT}` を単独の args 要素として渡し、その置換後の値を echo）
- `EXEC_ENV_ROOT=` / `EXEC_ENV_DATA=` / `EXEC_ENV_PROJ=` — `{command:"bash", args:["-c","... printenv CLAUDE_PLUGIN_ROOT ..."]}`（**env export** テスト。`${}` を使わず printenv で読むので launcher 事前置換の混入なし）
- `EXEC_MARKER form=execdirect ...` — `{command:"${CLAUDE_PLUGIN_ROOT}/hooks/exec-marker.sh", args:["execdirect"]}`（command 自体に placeholder。直接 spawn が成功した場合のみ出る）
- `EXEC_MARKER form=execbash ...` — `{command:"bash", args:["${CLAUDE_PLUGIN_ROOT}/hooks/exec-marker.sh","execbash"]}`（args 要素に placeholder。bash が script を読めた場合のみ出る）
- `EXEC_ECHO_BUILTIN=` — `{command:"echo", args:["EXEC_ECHO_BUILTIN=reached"]}`（builtin/非 .exe 名が exec form の command として解決できるかのテスト）
- `EXEC_HOST=` / `EXEC_WSL_LIB=` / `EXEC_MNT_C=` — exec form の bash がどの環境で実行されたかの WSL 再確認

## 判定の見方

**観測基盤**
- `EXEC_CONTROL=static_no_var` が無い → exec form の `{command:"bash"}` がそもそも解決/surface していない（host 側で `bash` が exec form の実行可能ファイルとして解決できない、の可能性。この時点で多くの bash 系観測点が silent になる前提で他を読む）。

**機構 1：launcher のテキスト事前置換（最重要）**
- `EXEC_ARGS_PLACEHOLDER=[/実際のパス...]` → **exec form では placeholder が実 path に置換される**。shell form §2.2（`/hooks/x.sh` に化けた）を覆す決定打。
- `EXEC_ARGS_PLACEHOLDER=[]`（空） → 置換は走るが値が empty（env と同じ供給源。path 解決は依然 dead）。
- `EXEC_ARGS_PLACEHOLDER=[${CLAUDE_PLUGIN_ROOT}]` literal → exec form でも事前置換が走らない。

**機構 2：env export（機構 1 と独立）**
- `EXEC_ENV_ROOT=[/実際のパス...]` → exec form では env に値が入る。shell form §2.1（empty）を覆す。
- `EXEC_ENV_ROOT=[]`（空） → env export も empty。§2.1 と一致（exec form でも env は来ない）。
- DATA / PROJ も同様に読む。

**機構 1 と 2 はドキュメント上「両方効く」とされる。実機でどちらが効く/効かないかの 2×2 が今回の核心：**

| ARGS_PLACEHOLDER | ENV_ROOT | 解釈 |
|---|---|---|
| 実パス | 実パス | ドキュメント通り。path 解決可。前回の「path 解決 dead」結論は exec form で覆る |
| 実パス | 空 | テキスト事前置換は効く / env は来ない。`args` に直接書けば解決できる |
| 空 | 空 | どちらも empty。Cowork plugin-level hook では exec form でも値が無い（§2.1 の壁は form 非依存） |
| literal | 空 | exec form でも事前置換すら走らない（最も悲観的） |

**機構 3：script 起動（execdirect vs execbash）**
- `EXEC_MARKER form=execbash` が出る → args 要素の placeholder が実 path に解決され bash が script を読めた（機構 1 が path として機能した証拠）。
- `EXEC_MARKER form=execdirect` が出る → command 直書きの placeholder も解決され、かつ .sh が host で直接 spawn 可能だった。
- execbash だけ出て execdirect が無い → 置換は効くが「Windows exec form は実 .exe が必要」の caveat で .sh 直接 spawn が失敗（docs の Windows note と一致）。
- 両方無い → 機構 1 が path として機能していない（ARGS_PLACEHOLDER が空/literal のはず。整合確認）。
- MARKER 行内の `ROOT_ENV=[...]` は機構 2 の二重確認。

**機構 4：command 名の解決層**
- `EXEC_ECHO_BUILTIN=reached` が出る → `echo` が実行可能ファイルとして解決された（WSL 経路で `/bin/echo` 等）。
- 無い → builtin 名は exec form の command として解決不可（docs の「.cmd/.bat shim は実行不可」と同系の制約）。

**機構 5：実行環境（WSL 再確認）**
- `EXEC_HOST=` が Windows マシン名、`EXEC_WSL_LIB=present`、`EXEC_MNT_C=present` → exec form の bash も WSL2 で実行（shell form と同じ層）。
- いずれも absent / HOST=claude → exec form は別の層で実行されている。前回の WSL 委譲モデルを見直す材料。

## 最後に

各観測点の verdict を 1 行ずつ書き、上の 2×2 表のどのセルに該当したかを明記してください（例：「ARGS_PLACEHOLDER: 実パス / ENV_ROOT: 空 → セル『実パス×空』。exec form の args 経由なら path 解決可、env export は依然 dead」）。
