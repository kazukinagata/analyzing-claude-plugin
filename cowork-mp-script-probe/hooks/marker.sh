#!/usr/bin/env bash
# marker.sh — invoked from hooks.json via ${CLAUDE_PLUGIN_ROOT}/hooks/marker.sh.
# If this script runs at all, the variant prefix line below is emitted to the
# Claude context (plugin-level SessionStart stdout is surfaced as additional
# context). If the variant is missing from the context, the script was never
# reached — meaning ${CLAUDE_PLUGIN_ROOT} did not resolve in that hook command
# variant on the current install path (CLI / Cowork zip / Cowork marketplace).
form="${1:-unknown}"
echo "MP_SCRIPT_MARKER form=${form} reached=yes argv0=[$0] ROOT_ENV=[${CLAUDE_PLUGIN_ROOT:-(empty)}] DATA_ENV=[${CLAUDE_PLUGIN_DATA:-(empty)}] HOST=[$(hostname 2>/dev/null || echo unknown)]"
