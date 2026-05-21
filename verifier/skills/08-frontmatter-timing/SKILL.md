---
name: 08-frontmatter-timing
description: §1.8. Skill frontmatter hook registers AFTER first invoke. SessionStart + once:true does not fire. Self-block during own load is impossible.
user-invocable: true
hooks:
  SessionStart:
    - matcher: "startup|resume|clear|compact"
      hooks:
        - type: command
          once: true
          command: 'echo "[08-FM-SESSIONSTART unexpected fire] $(date -Iseconds)" >> "$CLAUDE_PROJECT_DIR/findings/${VERIFIER_VERSION_DIR:-v-unknown}/${CLAUDE_SESSION_ID:-no-sid}/probe.log" 2>/dev/null'
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'echo "[08-FM-PreToolUse fired] $(date -Iseconds)" >> "$CLAUDE_PROJECT_DIR/findings/${VERIFIER_VERSION_DIR:-v-unknown}/${CLAUDE_SESSION_ID:-no-sid}/probe.log" 2>/dev/null'
---

# 08-frontmatter-timing

§1.8 — skill frontmatter `SessionStart + once:true` は不発、`PreToolUse` は invoke 後の bash で発火。

## step 1: alive-check と log 確認

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
printf '[08-BODY %s] tag=alive-check\n' "$(date -Iseconds)" | tee -a "$out_dir/probe.log"
echo
echo "=== probe.log (SessionStart canary entries should be absent) ==="
grep -E "08-FM-SESSIONSTART|08-FM-PreToolUse" "$out_dir/probe.log" 2>&1 || echo "(no 08-FM lines)"
echo
echo "=== hooks.log (plugin-level session-start should be present) ==="
grep -c "tag=session-start" "$out_dir/hooks.log" 2>&1 || echo "0"
```

完了して exit、`./scripts/assert.sh 08`。
