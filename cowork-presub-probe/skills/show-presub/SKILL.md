---
name: show-presub
description: Surfaces the PRESUB marker lines that the plugin-level SessionStart hooks injected, so whether CLAUDE_PLUGIN_ROOT pre-substitution runs at the top level can be read off.
user-invocable: true
---

# show-presub

このプラグインの plugin-level SessionStart hook が、session 開始時に 5 種類の echo を実行して結果を context に注入しています。直前の context（system-reminder / additional context）から、以下のプレフィックスで始まる行を探して、一字一句そのまま全部貼ってください。無い種類は「無し」と答えてください。

- `PRESUB_CONTROL=` （変数なしの対照）
- `PRESUB_TOP_BARE=` （top-level `echo ${CLAUDE_PLUGIN_ROOT}`、裸）
- `PRESUB_TOP_SQ=` （top-level `echo '${CLAUDE_PLUGIN_ROOT}'`、single-quote でシェル展開を抑止 → 事前置換だけを観測）
- `PRESUB_DATA=` （top-level `echo ${CLAUDE_PLUGIN_DATA}`）
- `PRESUB_BASH_BRACE=` （`bash -c 'echo ${CLAUDE_PLUGIN_ROOT}'`）

判定の見方：

- 値が実パス（`/...` や `C:/...`）なら事前置換または env 展開が効いている。
- 値が literal `${CLAUDE_PLUGIN_ROOT}` のままなら事前置換が走っていない。
- `PRESUB_TOP_SQ` は single-quote でシェル展開を殺してあるので、ここが実パスなら **事前置換が走った証拠**、literal なら事前置換が走っていない証拠。
- `PRESUB_BASH_BRACE` が空なら「事前置換は走らず、bash の env 展開も空（env 未設定）」、実パスなら「事前置換が走った」。
