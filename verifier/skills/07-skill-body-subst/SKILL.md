---
name: 07-skill-body-subst
description: §1.7. Skill body ${VAR} substitution happens at invoke time only — reading the SKILL.md via Read tool returns literal placeholders.
user-invocable: true
---

# 07-skill-body-subst

CHECK_LINE: PLUGIN_ROOT_VALUE=${CLAUDE_PLUGIN_ROOT}

## step 1: invoke 経路での置換確認

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
{
  printf '[07-BODY %s] tag=alive-check\n' "$(date -Iseconds)"
  printf '[07-BODY] INVOKE_LINE: PLUGIN_ROOT_VALUE=${CLAUDE_PLUGIN_ROOT}\n'
} | tee -a "$out_dir/probe.log"
```

`./scripts/assert.sh 07` を叩く前に、**ユーザが別タスクで Read tool 経由の挙動を比較**してください（RUNBOOK 参照）。
