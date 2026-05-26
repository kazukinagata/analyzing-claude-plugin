#!/bin/sh
# verifier/hooks/subst-probe.sh — Log pre-substitution test results for probe 22.
#
# Each invocation appends one line to subst.log.
# Args: $1=tier (plugin|fm), $2=label, $3=value-as-shell-sees-it
#
# Caller is responsible for single-quote isolation in the hook command,
# so $3 contains the post-substitution value (if Claude Code pre-substitution
# ran) or the literal `${...}` token (if it did not).

tier="$1"
label="$2"
value="$3"
ts="$(date -Iseconds 2>/dev/null || date)"

proj="${CLAUDE_PROJECT_DIR:-$PWD}"
if [ -n "${VERIFIER_VERSION_DIR:-}" ]; then
  ver="$VERIFIER_VERSION_DIR"
else
  ver_raw="$(claude --version 2>/dev/null | awk '{print $1}')"
  if [ -n "$ver_raw" ]; then
    ver="v$ver_raw"
  else
    ver="v-unknown"
  fi
fi

out_dir="$proj/findings/$ver/probe-22"
mkdir -p "$out_dir"

printf '[%s][22-%s] %s=[%s]\n' "$ts" "$tier" "$label" "$value" >> "$out_dir/subst.log"
