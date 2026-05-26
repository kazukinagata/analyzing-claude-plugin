---
name: env-check
description: Dump CLAUDE_PLUGIN env vars across plugin-level hook, skill frontmatter hook, and skill body for Cowork env propagation re-verification.
user-invocable: true
hooks:
  SessionStart:
    - matcher: "startup|resume|clear|compact"
      hooks:
        - type: command
          command: 'bash -c ''echo "[FRONTMATTER-SessionStart] ROOT=[$CLAUDE_PLUGIN_ROOT] DATA=[$CLAUDE_PLUGIN_DATA] PROJECT=[$CLAUDE_PROJECT_DIR] OPT_HELLO=[$CLAUDE_PLUGIN_OPTION_HELLO_MESSAGE] HOST=[$(hostname)]"'''
  PreToolUse:
    - matcher: "Bash|mcp__workspace__bash"
      hooks:
        - type: command
          command: 'bash -c ''echo "[FRONTMATTER-PreToolUse] ROOT=[$CLAUDE_PLUGIN_ROOT] DATA=[$CLAUDE_PLUGIN_DATA] PROJECT=[$CLAUDE_PROJECT_DIR] HOST=[$(hostname)]"'''
---

# env-check

Cowork の env 伝播を再検証する probe です。frontmatter hook を SessionStart と PreToolUse の両方で仕掛けてあります。

## 手順

1. このskillを一度起動する（= frontmatter hook を登録させる）。次の bash を実行してください。

```bash
echo "[BODY] ROOT=[${CLAUDE_PLUGIN_ROOT:-(unset)}] DATA=[${CLAUDE_PLUGIN_DATA:-(unset)}] PROJECT=[${CLAUDE_PROJECT_DIR:-(unset)}] ENTRY=[${CLAUDE_CODE_ENTRYPOINT:-(unset)}] HOST=[$(hostname)]"
```

2. その後 session を一度 resume させる（ウィンドウを数分非アクティブにして戻る、もしくは新しいプロンプトを送る）。resume 時に SessionStart event が再発火します。

## 観測する行

画面に出た以下の行をすべて貼ってください。

- `[PLUGIN-HOOK SessionStart] ...`（plugin-level hook、session 開始 / resume 時）
- `[PLUGIN-HOOK PreToolUse] ...`（plugin-level hook、bash 直前）
- `[FRONTMATTER-SessionStart] ...`（この skill の frontmatter hook、SessionStart 経路）← 今回の主役
- `[FRONTMATTER-PreToolUse] ...`（この skill の frontmatter hook、PreToolUse 経路）
- `[BODY] ...`（skill body の bash）

`[FRONTMATTER-SessionStart]` 行が出れば frontmatter hook の env を直接観測できます。ROOT 等が空かどうかで判定します。
