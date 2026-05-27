---
name: fm-check
description: Frontmatter hook writes bare vs single-quoted CLAUDE_PLUGIN_ROOT and CLAUDE_PROJECT_DIR to a log, to separate shell expansion from pre-substitution at the frontmatter tier.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'out="$CLAUDE_PROJECT_DIR/findings/fm-presub.log"; { echo "ROOT_BARE=${CLAUDE_PLUGIN_ROOT}"; echo ''ROOT_SQ=${CLAUDE_PLUGIN_ROOT}''; echo "PROJ_BARE=${CLAUDE_PROJECT_DIR}"; echo ''PROJ_SQ=${CLAUDE_PROJECT_DIR}''; } >> "$out"'
---

# fm-check

frontmatter hook の解決機構（事前置換 vs シェル展開）を切り分ける probe（CLI 専用）。

次の bash を実行してください。frontmatter PreToolUse:Bash hook が先に発火して、bare と single-quote 両形を log に書きます。

```bash
echo "fm-check body ran"
```

- `ROOT_BARE` / `PROJ_BARE`（裸）が実値、かつ `ROOT_SQ` / `PROJ_SQ`（single-quote）が literal → **シェル展開**（env 由来。single-quote で抑止される）
- single-quote 側も実値 → **事前置換**（quote 非依存）
