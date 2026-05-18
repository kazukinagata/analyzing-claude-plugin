---
name: 19-cowork-resume
description: §2.1. Cowork re-fires SessionStart with source=resume after VM suspend. Skill frontmatter hooks reset across the resume. CLI baseline never resumes within one process.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'printf "[19-FM-still-registered %s]\n" "$(date -Iseconds)" >> "$CLAUDE_PROJECT_DIR/findings/v$(claude --version 2>/dev/null | awk "{print \$1}")/${CLAUDE_SESSION_ID:-no-sid}/probe.log"'
---

# 19-cowork-resume

§2.1 — Cowork で `SessionStart source=resume` の再発火 + frontmatter hook reset。

## step 1: alive-check (1st invoke)

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
printf '[19-BODY %s] tag=alive-check (1st invoke)\n' "$(date -Iseconds)" | tee -a "$out_dir/probe.log"
echo
echo "=== Now: unfocus Claude Desktop for 3 minutes to trigger VM suspend, then come back and re-invoke /verifier:19-cowork-resume ==="
echo
echo "=== After 2nd invoke, check: ==="
echo "- hooks.log: tag=session-start source=resume (additional row)"
echo "- probe.log: 19-FM-still-registered should appear AGAIN (frontmatter hook re-registered)"
```

完了して exit、しばらく待ってから再起動 → `./scripts/assert.sh 19`。
