---
name: uc2-check
description: post-2.1.207 の userConfig 仕様（shell-form hook は ${user_config.*} を拒否 / exec form は置換 / CLAUDE_PLUGIN_OPTION_<KEY> env / skill・agent content は非機密のみ置換）を Claude Desktop の Code タブと Cowork タブで実機検証する probe。skill body 側の置換結果を dump し、SessionStart hook が出した UC2-* 行と突き合わせる。
user-invocable: true
---

# uc2-check

**問い**: Claude Code 2.1.238 世代の userConfig は、Claude Desktop の **Code** と **Cowork** でそれぞれどこまで使えるか。

## A. skill body の置換（この節はモデルが読む時点で既に置換済み）

以下の行を **そのままコピーして報告**してください（`${...}` のままなら未置換、実値なら置換、`[sensitive option ...]` なら block）。

- BODY opt_plain=[${user_config.opt_plain}]
- BODY req_plain=[${user_config.req_plain}]
- BODY opt_secret=[${user_config.opt_secret}]
- BODY req_secret=[${user_config.req_secret}]
- BODY def_plain=[${user_config.def_plain}]
- BODY num_opt=[${user_config.num_opt}]
- BODY bool_opt=[${user_config.bool_opt}]
- BODY multi_opt=[${user_config.multi_opt}]

docs の主張は「Non-sensitive values can also be substituted in skill and agent content」。
つまり **非機密は実値／機密は不可** が期待値。`def_plain` は未入力にしてあるので、
ここに `DEFAULT-FROM-MANIFEST` が出れば **manifest の `default` が runtime に効いている**証拠。

## B. Bash tool（VM / subprocess）側から env が見えるか

次を Bash tool で実行し、出力を貼ってください。

```bash
echo "TOOL_HOST=$(hostname)"
env | sed -n 's/^\(CLAUDE_PLUGIN_OPTION_[A-Z0-9_]*\)=\(.*\)$/TOOL_ENV \1=[\2]/p' | sort
echo "TOOL_ENV_COUNT=$(env | grep -c '^CLAUDE_PLUGIN_OPTION_' || true)"
echo "TOOL_PLUGIN_ROOT=[${CLAUDE_PLUGIN_ROOT:-(unset)}]"
```

docs は env の対象を **"hook processes"** としか書いていない。Bash tool にも来るなら機密値の露出面が広がる（要記録）。

## C. hook 側の結果（SessionStart context から拾う）

セッション開始時の context にある以下の行を報告してください。

- `UC2-CTL shell_form_static=alive` … shell form の hook が生きている対照
- `UC2-CTL exec_form_static=alive` … exec form の hook が生きている対照
- `UC2-EXEC <key>=[...]` … **exec form での `${user_config.*}` 置換**（8 キー分。出ない行があれば silent skip）
- `UC2-ENV CLAUDE_PLUGIN_OPTION_*` … **env 経由**（`<ABSENT from env>` か実値か）

## D. 入力 UI の有無（目視）

1. plugin を install した直後、**入力フォーム/プロンプトが出たか**
2. plugin の設定画面から**後から編集できるか**（`/plugin configure` 相当の導線があるか）
3. `required: true` の 2 項目が未入力のまま install できてしまうか
4. `number` / `boolean` / `multiple: true` の項目が **専用 UI**（数値入力・トグル・複数行）で出るか、ただの text か
5. `sensitive: true` の 2 項目が **マスク表示**されるか

## 判定の型

| 面 | 期待（docs 準拠） | 実際 |
|---|---|---|
| shell-form hook + `${user_config.*}` | **エラーで実行されない**（violator plugin 側で検証） | ? |
| exec-form hook + `${user_config.*}` | 置換される | ? |
| `CLAUDE_PLUGIN_OPTION_<KEY>` (hook) | 全キー（機密含む）平文 | ? |
| skill body | 非機密=実値 / 機密=block | ? |
| `default` | 未入力時に default が入る | ? |
| 入力 UI | Code=あり / Cowork=? | ? |
