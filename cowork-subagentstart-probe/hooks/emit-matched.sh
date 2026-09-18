#!/usr/bin/env bash
# emit-matched.sh — SubagentStart hook scoped by matcher "sa-reporter".
# Same JSON channel as emit-json.sh, different marker, so we can tell whether
# SubagentStart honours a matcher (agent-name scoping) at all.
. "$(dirname "$0")/_lib.sh"

payload="$(cat 2>/dev/null || true)"
hint="$(sa_clean "$(sa_agent_hint "$payload")")"

sa_log "emit-matched ran at=$(date -Iseconds 2>/dev/null || echo no-date) hint=[${hint}]"

printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"SA-MATCHED additional_context=delivered channel=matcher(sa-reporter) agent_hint=[%s]"}}\n' \
  "$hint"
