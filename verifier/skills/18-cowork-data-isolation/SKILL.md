---
name: 18-cowork-data-isolation
description: §2.11 / §2.12. CLI shares CLAUDE_PLUGIN_DATA across sessions; Cowork isolates it per chat session. ROOT remains the same across sessions in both. CLAUDE_CODE_REMOTE is empty in both.
user-invocable: true
---

# 18-cowork-data-isolation

§2.11 — DATA は Cowork で chat session ごとに別 dir。CLI では共有。

## step 1: alive-check と marker 書き込み

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
marker="$(date +%s%N)-$(date -Iseconds)"
{
  printf '[18-BODY %s] tag=alive-check\n' "$(date -Iseconds)"
  printf '[18-BODY] CLAUDE_PLUGIN_ROOT=[%s]\n' "${CLAUDE_PLUGIN_ROOT-(unset)}"
  printf '[18-BODY] CLAUDE_PLUGIN_DATA=[%s]\n' "${CLAUDE_PLUGIN_DATA-(unset)}"
  printf '[18-BODY] CLAUDE_CODE_REMOTE=[%s]\n' "${CLAUDE_CODE_REMOTE-(unset)}"
  printf '[18-BODY] marker_to_write=[%s]\n' "$marker"
} | tee -a "$out_dir/probe.log"

if [ -n "$CLAUDE_PLUGIN_DATA" ]; then
  mkdir -p "$CLAUDE_PLUGIN_DATA" 2>/dev/null
  echo "$marker" > "$CLAUDE_PLUGIN_DATA/marker.txt" 2>&1
  echo "[18-BODY] read_back: $(cat "$CLAUDE_PLUGIN_DATA/marker.txt" 2>&1)" | tee -a "$out_dir/probe.log"
fi
```

## step 2: 別 chat で再起動した時のために MASTER-RUNBOOK に marker をメモ

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
echo "=== Copy this marker to MASTER-RUNBOOK 18 section: ==="
grep marker_to_write "$proj/findings/$ver/$sid/probe.log" | tail -1
echo
echo "=== suspend/resume protocol ==="
echo "Now keep the window unfocused for 3 minutes. Then re-invoke /verifier:18-cowork-data-isolation."
echo "marker.txt should still exist with the same value (same chat suspend/resume = persistent)."
echo
echo "=== cross-chat protocol ==="
echo "Then start a NEW chat session in the same project, invoke 18 again, and compare the read-back."
echo "Cowork: marker not found (per-chat isolation). CLI: same marker visible."
```

完了して exit、`./scripts/assert.sh 18`。
