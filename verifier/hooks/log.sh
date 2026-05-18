#!/bin/sh
# verifier/hooks/log.sh — Common logger for plugin-level hooks and skill frontmatter hooks.
#
# Output goes to:  $CLAUDE_PROJECT_DIR/findings/<version>/<sid>/hooks.log
# Lock file:        $CLAUDE_PROJECT_DIR/findings/<version>/<sid>/hooks.log.lock
#
# Designed for /bin/sh (dash on WSL Ubuntu). No bash-isms, no $RANDOM.
#
# Usage: log.sh <tag>
#   tag — short identifier for what triggered this entry (e.g. session-start, pretool-bash)

tag="$1"
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

# CLAUDE_SESSION_ID is set by Claude Code for plugin-level hooks (research §1.1).
# Fall back to a marker file if missing.
sid="${CLAUDE_SESSION_ID:-}"
if [ -z "$sid" ] && [ -r "$proj/findings/session-marker.txt" ]; then
  sid="$(cat "$proj/findings/session-marker.txt" 2>/dev/null)"
fi
sid="${sid:-no-sid}"

out_dir="$proj/findings/$ver/$sid"
out="$out_dir/hooks.log"
mkdir -p "$out_dir"

# Capture any stdin (hook payload, may be JSON or empty).
stdin_buf="$(cat 2>/dev/null || true)"

{
  if command -v flock >/dev/null 2>&1; then
    flock -x 9
  fi
  printf '\n=== [%s] tag=%s ===\n' "$ts" "$tag"
  printf 'env:\n'
  for v in CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA CLAUDE_PROJECT_DIR CLAUDE_CODE_REMOTE \
           CLAUDE_PLUGIN_OPTION_HELLO_MESSAGE CLAUDE_PLUGIN_OPTION_API_SECRET \
           CLAUDE_SKILL_DIR CLAUDE_SESSION_ID CLAUDE_CODE_ENTRYPOINT CLAUDE_CODE_EXECPATH; do
    eval "val=\${$v-(unset)}"
    printf '  %s=[%s]\n' "$v" "$val"
  done
  printf 'options(substituted): hello=[%s] secret=[%s]\n' \
    "${USER_CONFIG_HELLO:-}" "${USER_CONFIG_SECRET:-}"
  if [ -n "$stdin_buf" ]; then
    printf 'stdin:\n'
    printf '%s\n' "$stdin_buf"
  else
    printf 'stdin: (empty)\n'
  fi
} 9>>"$out.lock" >>"$out"
