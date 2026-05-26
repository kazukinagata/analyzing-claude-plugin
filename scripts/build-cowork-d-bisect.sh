#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
OUT_ABS="$(cd "findings/$(verifier_version_dir)" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

build_subset_real() {
  local label="$1"; shift
  local dest="$tmp/$label/verifier-$label"
  mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills"
  cp verifier/.claude-plugin/plugin.json "$dest/.claude-plugin/plugin.json"
  jq --arg n "verifier-$label" '.name=$n' "$dest/.claude-plugin/plugin.json" > "$dest/.claude-plugin/plugin.json.tmp"
  mv "$dest/.claude-plugin/plugin.json.tmp" "$dest/.claude-plugin/plugin.json"
  cp verifier/hooks/hooks.json "$dest/hooks/hooks.json"
  cp verifier/hooks/log.sh verifier/hooks/parallel-{a,b,c}.sh verifier/hooks/block.sh "$dest/hooks/"
  jq 'del(.hooks.UserPromptExpansion)' "$dest/hooks/hooks.json" > "$dest/hooks/hooks.json.tmp"
  mv "$dest/hooks/hooks.json.tmp" "$dest/hooks/hooks.json"
  for s in "$@"; do cp -r "verifier/skills/$s" "$dest/skills/$s"; done
  ( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
  echo "$OUT_ABS/verifier-$label.zip"
}

# Split second-half-no-suspects (11 skills) into two halves (all lowercase names)
Z1=$(build_subset_real cowork-d1-first 10-parallel-hook-firing 11-block-target 13-cowork-pretooluse 14-cowork-parser 15-cowork-file-io)
Z2=$(build_subset_real cowork-d2-second 16-cowork-path-forms 17-cowork-bash-mount 18-cowork-data-isolation 19-cowork-resume 20-cowork-validation 21-cowork-connected-folder)
Z3=$(build_subset_real cowork-d2a 16-cowork-path-forms 17-cowork-bash-mount 18-cowork-data-isolation)
Z4=$(build_subset_real cowork-d2b 19-cowork-resume 20-cowork-validation 21-cowork-connected-folder)
Z5=$(build_subset_real cowork-test-16 16-cowork-path-forms)
Z6=$(build_subset_real cowork-test-17 17-cowork-bash-mount)
Z7=$(build_subset_real cowork-test-18 18-cowork-data-isolation)

ls -la "$Z1" "$Z2"
cp "$Z1" "$Z2" "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/
ls "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/verifier-cowork-d{1,2}*.zip
