---
name: show-mp-disambig
description: Surfaces the MP_DA_* marker lines emitted by the plugin-level SessionStart hooks, used to disambiguate between (a) shell-bypass and (b) bash -c with $-escape models of Cowork hook execution.
user-invocable: true
---

# show-mp-disambig

このプラグインの plugin-level SessionStart hook が session 開始時に 8 種類のエントリを実行しています。直前の context（system-reminder / additional context / hook output として注入されたもの）から、以下のプレフィックスで始まる行を**全て一字一句そのまま**貼ってください。プレフィックスが見当たらない場合は「無し」と明記してください。

- `MP_DA_CONTROL=` （変数なしの対照、必ず出るはず）
- `MP_DA_DQ=` （`echo MP_DA_DQ="double-quoted"`）
- `MP_DA_DQ_INNER=` （`echo MP_DA_DQ_INNER=hello-"middle"-world`）
- `MP_DA_HOME=` （`echo MP_DA_HOME=$HOME`、bare）
- `MP_DA_HOME_BRACE=` （`echo MP_DA_HOME_BRACE=${HOME}`）
- `MP_DA_PATH=` （`echo MP_DA_PATH=$PATH`）
- `MP_DA_NUL=` （`echo MP_DA_NUL=$NO_SUCH_VAR_EXPECT_EMPTY`）
- `MP_DA_BASH_HOME=` （`bash -c 'echo MP_DA_BASH_HOME=$HOME'`）

判定の見方：

**Disambiguator A：double-quote**
- `MP_DA_DQ=double-quoted` → shell parser が走っている（double-quote が consume された）
- `MP_DA_DQ="double-quoted"` → shell parser を通っていない or `"` が escape されている
- `MP_DA_DQ_INNER=hello-middle-world` vs `hello-"middle"-world` も同様

**Disambiguator B：env が値を持つ `$VAR`**
- `MP_DA_HOME=/home/...` or `/c/Users/...` → shell parser + env 展開が走っている
- `MP_DA_HOME=$HOME` literal → shell parser が走っていない、または `$` が escape されている
- `MP_DA_PATH=` の挙動が同様（PATH は確実に env に値を持つ）

**Disambiguator C：unset env var**
- `MP_DA_NUL=` （空） → shell parser + env 展開が走っている（unset → empty に化けた）
- `MP_DA_NUL=$NO_SUCH_VAR_EXPECT_EMPTY` literal → shell parser を通っていない

**控え（既知）**
- `MP_DA_BASH_HOME=/home/...` → inner bash の展開で `$HOME` が解決（CLI でも Cowork でも展開できるはず。env を持ち込めれば）

最後に各観測点の verdict を 1 行ずつ書いてください（例：「DQ: literal で残った → shell bypass / HOME: literal $HOME → 同上 / NUL: empty → 矛盾」など）。
