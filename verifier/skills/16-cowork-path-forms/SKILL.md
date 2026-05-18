---
name: 16-cowork-path-forms
description: "CLAUDE_PLUGIN_ROOT and CLAUDE_PLUGIN_DATA take three different forms across contexts in Cowork (Windows, MSYS, Linux mount); CLI baseline is a single Linux path (research sections 2.8 and 7.9)."
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'sid="${CLAUDE_SESSION_ID:-no-sid}"; ver="v$(claude --version 2>/dev/null | awk "{print \$1}")"; out_dir="$CLAUDE_PROJECT_DIR/findings/$ver/$sid"; mkdir -p "$out_dir"; printf "[16-FM HOOK_SUBST] ROOT=[${CLAUDE_PLUGIN_ROOT}]\n[16-FM HOOK_ENV] ROOT=[%s] DATA=[%s]\n" "${CLAUDE_PLUGIN_ROOT:-(empty)}" "${CLAUDE_PLUGIN_DATA:-(empty)}" >> "$out_dir/probe.log"'
---

# 16-cowork-path-forms

§2.8 — `CLAUDE_PLUGIN_ROOT/DATA` の 3 形式。

## step 1: skill body 経路で alive-check と path 観察

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
{
  printf '[16-BODY %s] tag=alive-check\n' "$(date -Iseconds)"
  printf '[16-BODY BODY_SUBST] ROOT=[${CLAUDE_PLUGIN_ROOT}] DATA=[${CLAUDE_PLUGIN_DATA}]\n'
  printf '[16-BODY BODY_ENV] ROOT=[%s] DATA=[%s]\n' "${CLAUDE_PLUGIN_ROOT-(unset)}" "${CLAUDE_PLUGIN_DATA-(unset)}"
} | tee -a "$out_dir/probe.log"
echo
echo "=== 3 forms of ROOT/DATA in probe.log ==="
grep -E "BODY_SUBST|HOOK_SUBST|HOOK_ENV" "$out_dir/probe.log"
```

完了して exit、`./scripts/assert.sh 16`。
