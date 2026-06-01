#!/usr/bin/env bash
# persist.sh — runs from a plugin-level SessionStart hook (host side).
#
# Goal: decide whether a value written to $CLAUDE_PLUGIN_DATA survives ACROSS
# Cowork chat sessions. On Mac Cowork only the host hook has CLAUDE_PLUGIN_DATA
# set (the VM Bash tool / skill body has it UNSET — see findings OBS-3), so the
# write AND the read-back must both happen here, in the hook, and be surfaced via
# SessionStart stdout (which is injected into context).
#
# Each invocation:
#   1. prints the live $CLAUDE_PLUGIN_DATA path + a path-hash, so we can see if
#      the data dir itself changes between sessions.
#   2. reads back the marker file written by PREVIOUS sessions (the cross-session
#      evidence) and prints every prior line.
#   3. appends one new line tagged with this session's id, then prints the new
#      total line count.
#
# Read the verdict from the surfaced lines:
#   - DP_PRIOR_COUNT grows 0 -> 1 -> 2 ... across separate chat sessions, and
#     DP_PRIOR lines from earlier sessions are still listed  => DATA PERSISTS
#     across Cowork sessions (and the data dir path is stable).
#   - DP_PRIOR_COUNT is always 0 / file always absent, and DP_DATA_HASH changes
#     every session  => DATA is per-session ISOLATED (fresh dir each chat).

data="${CLAUDE_PLUGIN_DATA:-}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
host="$(hostname 2>/dev/null || echo unknown)"
stamp="$(date -Iseconds 2>/dev/null || echo no-date)"

echo "DP_MARKER reached=yes argv0=[$0] DATA_ENV=[${data:-(empty)}] HOST=[${host}] SID=[${sid}]"

if [ -z "$data" ]; then
  echo "DP_MARKER data_unset=yes -> cannot test persistence (CLAUDE_PLUGIN_DATA empty in this hook env)"
  exit 0
fi

# path-hash: stable fingerprint of the data dir path so we can tell at a glance
# whether the SAME directory is handed back across sessions.
data_hash="$(printf '%s' "$data" | cksum 2>/dev/null | awk '{print $1}')"
echo "DP_DATA_HASH=[${data_hash}] (cksum of the DATA path string; same number across sessions => same dir)"

mkdir -p "$data" 2>/dev/null
marker="$data/persist-marker.log"

# --- read back what earlier sessions wrote (BEFORE we append our own) ---
if [ -f "$marker" ]; then
  prior_count="$(grep -c . "$marker" 2>/dev/null || echo 0)"
  echo "DP_PRIOR_COUNT=[${prior_count}] (lines written by previous sessions, before this one appends)"
  # echo each prior line so cross-session survival is visible in context
  while IFS= read -r line; do
    echo "DP_PRIOR ${line}"
  done < "$marker"
else
  echo "DP_PRIOR_COUNT=[0] (no marker file yet — this is the first session to write, OR the dir was fresh)"
fi

# --- append this session's marker ---
echo "sid=${sid} at=${stamp} data_hash=${data_hash}" >> "$marker" 2>/dev/null
new_total="$(grep -c . "$marker" 2>/dev/null || echo 0)"
echo "DP_AFTER_WRITE_TOTAL=[${new_total}] (line count after this session appended; should be PRIOR_COUNT+1)"
echo "DP_READBACK_LAST=[$(tail -1 "$marker" 2>&1)]"
