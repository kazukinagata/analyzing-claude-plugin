#!/usr/bin/env bash
# scripts/package-cowork.sh — Build zip artifacts for Cowork upload.
#
# Outputs:
#   findings/v<VER>/verifier-cowork.zip                — main plugin with UserPromptExpansion stripped
#   findings/v<VER>/verifier-violator-userpromptexpansion.zip — probe 20a variant
#   findings/v<VER>/verifier-violator-uppercase-name.zip      — probe 20b variant
#
# UserPromptExpansion is stripped from the main hooks.json because Cowork
# rejects whole plugins that include this event (§2.3).
set -uo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=./_env.sh
. scripts/_env.sh

VER="$(verifier_version_dir)"
out_dir="findings/$VER"
mkdir -p "$out_dir"

if ! command -v zip >/dev/null 2>&1; then
  echo "zip command not found. Install with: sudo apt install zip" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq command not found. Install with: sudo apt install jq" >&2
  exit 2
fi

tmp_root="$(mktemp -d -t analyzing-claude-plugin-cowork-XXXXXX)"
trap 'rm -rf "$tmp_root"' EXIT

# Copy verifier/ into a tmp dir, then strip UserPromptExpansion from hooks.json
echo "Building Cowork-safe verifier/"
cp -a verifier "$tmp_root/verifier"
jq 'del(.hooks.UserPromptExpansion)' "$tmp_root/verifier/hooks/hooks.json" \
  > "$tmp_root/verifier/hooks/hooks.json.tmp"
mv "$tmp_root/verifier/hooks/hooks.json.tmp" "$tmp_root/verifier/hooks/hooks.json"
echo "  stripped UserPromptExpansion from hooks.json"

zip_target="$(pwd)/$out_dir/verifier-cowork.zip"
rm -f "$zip_target"
(cd "$tmp_root" && zip -r "$zip_target" verifier >/dev/null)
echo "  -> $out_dir/verifier-cowork.zip ($(du -h "$zip_target" | awk '{print $1}'))"

# Build separate violator variants for probe 20.
# These are standalone plugins each with a single violation, so Cowork
# validation surfaces them individually.
for variant in verifier-violator-userpromptexpansion verifier-violator-uppercase-name; do
  src="$variant"
  if [ ! -d "$src" ]; then
    echo "  (skipping $variant — directory not present)"
    continue
  fi
  zt="$(pwd)/$out_dir/${variant}.zip"
  rm -f "$zt"
  (cd "$(pwd)" && zip -r "$zt" "$variant" -x '*/.git/*' >/dev/null)
  echo "  -> $out_dir/${variant}.zip ($(du -h "$zt" | awk '{print $1}'))"
done

echo
echo "Done. Upload to Cowork via Claude Desktop UI; see docs/cowork-runbook.md."
