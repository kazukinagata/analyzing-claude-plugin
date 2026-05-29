#!/usr/bin/env bash
# exec-marker.sh — launched from hooks.json EXEC FORM entries (args present).
#
# Two entries reach this script:
#   form=execdirect : command="${CLAUDE_PLUGIN_ROOT}/hooks/exec-marker.sh", args=["execdirect"]
#                     -> launcher pre-substitutes the placeholder INTO command, then spawns
#                        the script directly (no shell). Needs the placeholder to resolve to a
#                        real path AND the .sh to be spawnable as a real executable on the host.
#   form=execbash   : command="bash", args=["${CLAUDE_PLUGIN_ROOT}/hooks/exec-marker.sh","execbash"]
#                     -> launcher pre-substitutes the placeholder INTO an args element, bash reads
#                        the script. Robust against the "Windows exec form needs a real .exe" caveat.
#
# If a form's line is absent from the Claude context, that variant never launched
# -> the ${CLAUDE_PLUGIN_ROOT} placeholder did not resolve to a real path in that variant.
# printenv is used (not ${VAR}) so the launcher's ${...} placeholder pre-substitution
# can't contaminate the env-export reading.
form="${1:-unknown}"
echo "EXEC_MARKER form=${form} reached=yes argv0=[$0] ROOT_ENV=[$(printenv CLAUDE_PLUGIN_ROOT)] DATA_ENV=[$(printenv CLAUDE_PLUGIN_DATA)] HOST=[$(hostname 2>/dev/null || echo unknown)]"
