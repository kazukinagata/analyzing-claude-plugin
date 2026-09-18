#!/usr/bin/env bash
# replay-log.sh — PostToolUse(Agent|Task) hook, runs in the MAIN session after
# the subagent call returns. Prints the host-side execution log written by the
# SubagentStart hooks.
#
# Why it matters: if the subagent reports no SA-* markers, this tells us which
# failure we hit —
#   SA-EXECLOG lines present  => the SubagentStart hooks DID run; their output
#                                was dropped on the way into the subagent.
#   SA-EXECLOG count=0        => the SubagentStart event never fired at all.
. "$(dirname "$0")/_lib.sh"

cat >/dev/null 2>&1 || true   # drain the hook payload, keep stdout clean
log="$(sa_logfile)"

if [ -f "$log" ]; then
  n="$(grep -c . "$log" 2>/dev/null || echo 0)"
  echo "SA-EXECLOG count=[${n}] file=[${log}]"
  while IFS= read -r line; do
    echo "SA-EXECLOG ${line}"
  done < "$log"
else
  echo "SA-EXECLOG count=[0] file=[${log}] (no log file — SubagentStart hooks never executed on this host, or the hook filesystem is not shared)"
fi
