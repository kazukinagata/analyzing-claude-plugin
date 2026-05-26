---
name: show-expansion
description: Surfaces the EXP_ marker lines that the plugin-level SessionStart hooks injected, so the top-level vs bash -c expansion behavior can be read off.
user-invocable: true
---

# show-expansion

このプラグインの plugin-level SessionStart hook が、session 開始時に 5 種類の echo を実行して結果を context に注入しています。直前の context（system-reminder / additional context）から、以下のプレフィックスで始まる行を探して、一字一句そのまま全部貼ってください。無い種類は「無し」と答えてください。

- `EXP_CONTROL=` （変数なしの対照）
- `EXP_TOP_DOLLAR=` （top-level `echo $PATH`）
- `EXP_TOP_BRACE=` （top-level `echo ${PATH}`）
- `EXP_BASH_DOLLAR=` （`bash -c 'echo $PATH'`）
- `EXP_BRACKET_` または `[[ -d /tmp ]]` を含む行 （top-level の bash 構文）

判定の見方：

- `EXP_TOP_DOLLAR` が実際の PATH 値なら top-level でシェル展開が効いている。`$PATH` という literal のままなら展開されていない。
- `EXP_BASH_DOLLAR` が実 PATH 値なら `bash -c` 経由では展開が効く。
- bracket 行が `[[ -d /tmp ]] && ...` の literal で出ていれば、top-level の bash 構文が評価されていない。
