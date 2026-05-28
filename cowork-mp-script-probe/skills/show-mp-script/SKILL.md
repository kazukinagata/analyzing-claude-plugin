---
name: show-mp-script
description: Surfaces the MP_SCRIPT_* marker lines that the plugin-level SessionStart hooks emitted, to determine whether ${CLAUDE_PLUGIN_ROOT}/hooks/marker.sh actually launched in each command-form variant on the current install path.
user-invocable: true
---

# show-mp-script

このプラグインの plugin-level SessionStart hook が session 開始時に 5 種類のエントリを実行しています。直前の context（system-reminder / additional context / hook output として注入されたもの）から、以下のプレフィックスで始まる行を**全て一字一句そのまま**貼ってください。プレフィックスが見当たらない場合は「無し」と明記してください。

- `MP_SCRIPT_CONTROL=` （変数なしの対照、必ず出るはず）
- `MP_SCRIPT_ECHO_BARE=` （top-level `echo ${CLAUDE_PLUGIN_ROOT}`、裸）
- `MP_SCRIPT_ECHO_SQ=` （top-level `echo '${CLAUDE_PLUGIN_ROOT}'`、single-quote で shell 展開を抑止）
- `MP_SCRIPT_MARKER form=topbare ...` （top-level の `"${CLAUDE_PLUGIN_ROOT}/hooks/marker.sh" topbare` が起動した場合のみ marker.sh が echo する）
- `MP_SCRIPT_MARKER form=bashbrace ...` （`bash -c '"$CLAUDE_PLUGIN_ROOT/hooks/marker.sh" bashbrace'` が起動した場合のみ marker.sh が echo する）

判定の見方：

- `MP_SCRIPT_CONTROL` が無い ＝ そもそも plugin-level SessionStart hook が surface していない（観測基盤側の問題、§2.10 系）。
- `MP_SCRIPT_ECHO_BARE` の値が実パス ＝ 当該 install 経路で env シェル展開が効いている。空 or literal `${CLAUDE_PLUGIN_ROOT}` ＝ 効いていない。
- `MP_SCRIPT_ECHO_SQ` の値が literal `${CLAUDE_PLUGIN_ROOT}` ＝ 事前置換が走っていない。実パスに置換されていたら事前置換が走っている証拠。
- `MP_SCRIPT_MARKER form=topbare` の行が出ている ＝ top-level の `"${CLAUDE_PLUGIN_ROOT}/hooks/marker.sh"` が実際にスクリプトを起動できた。
- `MP_SCRIPT_MARKER form=bashbrace` の行が出ている ＝ `bash -c` wrap 経由でスクリプトを起動できた。

マーカー行を貼った後に、各変種の verdict を 1 行ずつ簡潔にコメントしてください（例：「ECHO_BARE: 実パス resolve / MARKER topbare: 起動した / MARKER bashbrace: 起動しなかった」）。
