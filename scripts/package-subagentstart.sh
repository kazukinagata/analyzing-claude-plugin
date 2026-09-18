#!/usr/bin/env bash
# package-subagentstart.sh — Build the zip for the SubagentStart additionalContext probe.
#
#   dist/cowork-subagentstart-probe.zip
#
# Layout matches the other Cowork probes: the plugin directory sits at the
# archive root, so the Claude Desktop plugin uploader accepts it as-is.
set -uo pipefail
cd "$(dirname "$0")/.."

command -v zip >/dev/null 2>&1 || { echo "zip not found" >&2; exit 2; }
mkdir -p dist

p=cowork-subagentstart-probe
[ -d "$p" ] || { echo "missing $p" >&2; exit 2; }
python3 -c "import json; json.load(open('$p/.claude-plugin/plugin.json'))" || exit 2
python3 -c "import json; json.load(open('$p/hooks/hooks.json'))" || exit 2
chmod +x "$p"/hooks/*.sh
rm -f "dist/$p.zip"
zip -r "dist/$p.zip" "$p" -x '*/.DS_Store' '*/.git/*' >/dev/null
echo "  -> dist/$p.zip ($(du -h "dist/$p.zip" | awk '{print $1}'))"
