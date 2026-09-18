#!/usr/bin/env bash
# emit-json.sh — matcher-less SubagentStart hook.
# Emits ONLY a JSON object using hookSpecificOutput.additionalContext, which is
# the documented way to inject text into the starting subagent's context.
# If SA-JSON shows up inside the subagent, additionalContext injection works.
. "$(dirname "$0")/_lib.sh"

payload="$(cat 2>/dev/null || true)"
hint="$(sa_clean "$(sa_agent_hint "$payload")")"
plen="$(printf '%s' "$payload" | wc -c | tr -d ' ')"
host="$(sa_clean "$(hostname 2>/dev/null || echo unknown)")"
root_set=no; [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && root_set=yes
sid="$(sa_clean "${CLAUDE_SESSION_ID:-unset}")"

sa_log "emit-json ran at=$(date -Iseconds 2>/dev/null || echo no-date) payload_bytes=${plen} hint=[${hint}]"

printf '{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":"SA-JSON additional_context=delivered channel=matcherless payload_bytes=%s agent_hint=[%s] host=[%s] plugin_root_set=%s session=[%s]"}}\n' \
  "$plen" "$hint" "$host" "$root_set" "$sid"
