#!/usr/bin/env bash
# Build verifier-cowork.zip but EXCLUDE the 03-shell-binsh skill (which triggers Cowork validator rejection).
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
OUT_ABS="$(cd "findings/$(verifier_version_dir)" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cp -a verifier "$tmp/verifier"
rm -rf "$tmp/verifier/skills/03-shell-binsh"
# strip UserPromptExpansion like package-cowork.sh
jq 'del(.hooks.UserPromptExpansion)' "$tmp/verifier/hooks/hooks.json" > "$tmp/verifier/hooks/hooks.json.tmp"
mv "$tmp/verifier/hooks/hooks.json.tmp" "$tmp/verifier/hooks/hooks.json"

ZIP="$OUT_ABS/verifier-cowork-no-03.zip"
rm -f "$ZIP"
( cd "$tmp" && zip -r "$ZIP" verifier >/dev/null )
ls -la "$ZIP"
cp "$ZIP" "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/
ls -la "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/verifier-cowork-no-03.zip
