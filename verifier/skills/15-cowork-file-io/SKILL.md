---
name: 15-cowork-file-io
description: §2.7. In Cowork, hook side effects (file writes) don't reach the shell sandbox. Only stdout/additionalContext flows through. This probe writes a canary file from a hook (via the inline command below) then tries to read it from Bash tool.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'ts=$(date +%s%N); marker_path="/tmp/file-io-canary-$ts.txt"; printf "[15-FM marker_path=%s wrote_at=%s]" "$marker_path" "$(date -Iseconds)" > "$marker_path" 2>/dev/null; printf "[15-FM-hook fired marker_path=%s]\n" "$marker_path" >> "$CLAUDE_PROJECT_DIR/findings/v$(claude --version 2>/dev/null | awk "{print \$1}")/${CLAUDE_SESSION_ID:-no-sid}/probe.log" 2>/dev/null'
---

# 15-cowork-file-io

§2.7 — Cowork で hook 内 file write が届かない。

## step 1: alive-check と canary 確認

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
{
  printf '[15-BODY %s] tag=alive-check\n' "$(date -Iseconds)"
  printf '[15-BODY] file-io-canary files in /tmp:\n'
  ls -la /tmp/file-io-canary-*.txt 2>&1
} | tee -a "$out_dir/probe.log"
echo
echo "=== probe.log: 15-FM-hook lines (proves hook was called) ==="
grep "15-FM-hook" "$out_dir/probe.log" 2>&1
```

完了して exit、`./scripts/assert.sh 15`。
