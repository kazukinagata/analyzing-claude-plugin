#!/usr/bin/env bash
# _lib.sh — shared helpers for the SubagentStart probe hooks.
# Sourced by emit-json.sh / emit-matched.sh / replay-log.sh.
#
# Design constraints (from earlier Cowork findings):
#   - a hook's stdout is the ONLY channel that reaches model context, and any
#     redirect operator in the hooks.json command string kills that stdout
#     (team-report §2.2) -> all file writes happen inside these scripts.
#   - for a hook whose output must be parsed as JSON, stdout has to be the JSON
#     object and nothing else -> diagnostics are carried INSIDE additionalContext.

# where the host-side execution log lives (see replay-log.sh)
sa_logfile() {
  local dir="${CLAUDE_PLUGIN_DATA:-}"
  if [ -z "$dir" ] || ! mkdir -p "$dir" 2>/dev/null; then
    dir="${TMPDIR:-/tmp}"
  fi
  printf '%s/sa-subagentstart-exec.log' "$dir"
}

# strip anything that would break a one-line JSON string literal
sa_clean() {
  printf '%s' "$1" | tr -d '"\\\n\r\t' | cut -c1-300
}

# crude, dependency-free peek at the hook stdin payload: pull out the
# agent-ish key/value pairs without needing python/jq on the host.
sa_agent_hint() {
  local payload="$1"
  printf '%s' "$payload" \
    | tr ',{}' '\n\n\n' \
    | grep -i -E 'agent|subagent' \
    | tr -d '"' \
    | tr '\n' ' '
}

# one line appended per hook execution; replay-log.sh surfaces these to the
# MAIN session so "hook never ran" can be told apart from "output was dropped".
sa_log() {
  printf '%s\n' "$1" >> "$(sa_logfile)" 2>/dev/null || true
}
