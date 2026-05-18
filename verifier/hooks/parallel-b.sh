#!/bin/sh
# Parallel firing probe (§1.10). Sleep 400ms — should finish AFTER parallel-a if run in parallel.
start_ns="$(date +%s%N 2>/dev/null || echo 0)"
sleep 0.4
end_ns="$(date +%s%N 2>/dev/null || echo 0)"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
if [ -n "${VERIFIER_VERSION_DIR:-}" ]; then
  ver="$VERIFIER_VERSION_DIR"
else
  ver_raw="$(claude --version 2>/dev/null | awk '{print $1}')"
  ver="v${ver_raw:-unknown}"
fi
sid="${CLAUDE_SESSION_ID:-no-sid}"
out="$proj/findings/$ver/$sid/hooks.log"
mkdir -p "$(dirname "$out")"
{
  if command -v flock >/dev/null 2>&1; then
    flock -x 9
  fi
  printf '\n=== tag=parallel-b-start ts=%s pid=%d ===\n' "$start_ns" "$$"
  printf '=== tag=parallel-b-end   ts=%s pid=%d ===\n' "$end_ns" "$$"
} 9>>"$out.lock" >>"$out"
