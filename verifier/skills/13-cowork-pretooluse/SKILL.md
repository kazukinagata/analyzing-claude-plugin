---
name: 13-cowork-pretooluse
description: "Cowork plugin-level PreToolUse never fires (block ignored) and bash tool is named mcp__workspace__bash (research sections 2.4 and 2.5). CLI baseline confirms block fires for the Bash matcher."
user-invocable: true
---

# 13-cowork-pretooluse

§2.5 — Cowork で plugin-level `PreToolUse` の block 試行が無視される。bash tool 名は `mcp__workspace__bash`。

**CLI で実際の block 観察をするには**、デフォルトの hooks.json では block.sh を呼び出していないため、`docs/cowork-runbook.md` の "13 CLI baseline" の手順に従い、`hooks-block.json` variant を一時的に有効化してください。本 SKILL は CLI 既定の hooks.json で動かしてもログ書き出しまでは確認できます。

## step 1: alive-check と Bash の test marker

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
{
  printf '[13-BODY %s] tag=alive-check\n' "$(date -Iseconds)"
  printf '[13-BODY] TEST_BASH_OK_MARKER (CLI without block hook: appears; CLI with block hook: should not appear; Cowork: should appear)\n'
  printf '[13-BODY] CLAUDE_CODE_ENTRYPOINT=[%s]\n' "${CLAUDE_CODE_ENTRYPOINT-(unset)}"
} | tee -a "$out_dir/probe.log"

echo
echo "=== hooks.log block-attempted / pretool entries ==="
grep -E "tag=block-attempted|tag=pretool-bash|tag=pretool-mcp-workspace-bash" "$out_dir/hooks.log" 2>&1 || echo "(none)"
```

## step 2: tool 名の直接観察（transcript 経由）

```bash
echo "Cowork で本 probe を回した場合は、Claude Desktop の transcript 上で"
echo "  tool_name=\"mcp__workspace__bash\""
echo "となっているかを目視で確認してください（§2.4）。"
echo
echo "本セッションの hooks.log タグ一覧:"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
grep -oE "tag=[a-z-]+" "$proj/findings/$ver/$sid/hooks.log" 2>/dev/null | sort -u
```

完了して exit、`./scripts/assert.sh 13`。
