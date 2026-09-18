#!/usr/bin/env bash
# package-userconfig2.sh — Build the two zips for the userConfig re-probe
# (Claude Desktop: Code tab + Cowork tab). Each zip contains the plugin
# directory at the archive root, matching the layout the other Cowork probes use.
#
#   dist/cowork-userconfig2-probe.zip        main probe (exec form + env + body + agent)
#   dist/userconfig2-shellform-violator.zip  isolated shell-form ${user_config.*} violator
set -uo pipefail
cd "$(dirname "$0")/.."

command -v zip >/dev/null 2>&1 || { echo "zip not found" >&2; exit 2; }
mkdir -p dist

for p in cowork-userconfig2-probe userconfig2-shellform-violator; do
  [ -d "$p" ] || { echo "missing $p" >&2; exit 2; }
  # keep the manifest honest before shipping
  python3 -c "import json,sys; json.load(open('$p/.claude-plugin/plugin.json'))" || exit 2
  python3 -c "import json,sys; json.load(open('$p/hooks/hooks.json'))" || exit 2
  rm -f "dist/$p.zip"
  zip -r "dist/$p.zip" "$p" -x '*/.DS_Store' '*/.git/*' >/dev/null
  echo "  -> dist/$p.zip ($(du -h "dist/$p.zip" | awk '{print $1}'))"
done
echo
echo "Install both via the Claude Desktop plugin UI (Code tab, then a Cowork session)."
