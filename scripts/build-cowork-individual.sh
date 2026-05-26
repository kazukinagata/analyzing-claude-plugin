#!/usr/bin/env bash
# Test each skill individually (with 00-canary baseline) to find ALL Cowork-incompat skills.
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
OUT_ABS="$(cd "findings/$(verifier_version_dir)" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

build_individual() {
  local skill="$1"
  local label="cowork-test-$skill"
  local dest="$tmp/$label/verifier-$label"
  mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills"
  cp verifier/.claude-plugin/plugin.json "$dest/.claude-plugin/plugin.json"
  jq --arg n "verifier-$label" '.name=$n' "$dest/.claude-plugin/plugin.json" > "$dest/.claude-plugin/plugin.json.tmp"
  mv "$dest/.claude-plugin/plugin.json.tmp" "$dest/.claude-plugin/plugin.json"
  cp verifier/hooks/hooks.json "$dest/hooks/hooks.json"
  cp verifier/hooks/log.sh verifier/hooks/parallel-{a,b,c}.sh verifier/hooks/block.sh "$dest/hooks/"
  jq 'del(.hooks.UserPromptExpansion)' "$dest/hooks/hooks.json" > "$dest/hooks/hooks.json.tmp"
  mv "$dest/hooks/hooks.json.tmp" "$dest/hooks/hooks.json"
  cp -r verifier/skills/00-canary "$dest/skills/"
  cp -r "verifier/skills/$skill" "$dest/skills/$skill"
  ( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
}

NEW_ZIPS=()
# Cumulative threshold tests: real skills at increasing counts
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

NEW_ZIPS+=("$(build_subset_real cowork-count4 00-canary 01-env-propagation 02-substitution-allowlist 04-sensitive-leak)")
NEW_ZIPS+=("$(build_subset_real cowork-count5 00-canary 01-env-propagation 02-substitution-allowlist 04-sensitive-leak 05-userconfig-trigger)")
NEW_ZIPS+=("$(build_subset_real cowork-count6 00-canary 01-env-propagation 02-substitution-allowlist 04-sensitive-leak 05-userconfig-trigger 06-marketplace-cache)")
NEW_ZIPS+=("$(build_subset_real cowork-count7 00-canary 01-env-propagation 02-substitution-allowlist 04-sensitive-leak 05-userconfig-trigger 06-marketplace-cache 07-skill-body-subst)")
NEW_ZIPS+=("$(build_subset_real cowork-count8-add09 00-canary 01-env-propagation 02-substitution-allowlist 04-sensitive-leak 05-userconfig-trigger 06-marketplace-cache 07-skill-body-subst 09-slash-vs-natural)")

ls -la "${NEW_ZIPS[@]}"
cp "${NEW_ZIPS[@]}" "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/
ls "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/verifier-cowork-test-*.zip
