#!/bin/sh
# verifier/hooks/block.sh — Emit a PreToolUse block decision and log the attempt.
#
# Usage: block.sh <matcher-tag> <reason>
# Used by probe 13-cowork-pretooluse.

matcher_tag="$1"
reason="$2"
ts="$(date -Iseconds 2>/dev/null || date)"
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
if [ -n "${VERIFIER_VERSION_DIR:-}" ]; then
  ver="$VERIFIER_VERSION_DIR"
else
  ver_raw="$(claude --version 2>/dev/null | awk '{print $1}')"
  ver="v${ver_raw:-unknown}"
fi
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
out="$out_dir/hooks.log"
mkdir -p "$out_dir"

{
  if command -v flock >/dev/null 2>&1; then
    flock -x 9
  fi
  printf '\n=== [%s] tag=block-attempted matcher=%s ===\n' "$ts" "$matcher_tag"
  printf 'reason: %s\n' "$reason"
} 9>>"$out.lock" >>"$out"

# Emit the actual block decision on stdout (Claude Code reads this).
printf '{"decision":"block","reason":"%s (matcher=%s)"}\n' "$reason" "$matcher_tag"
