#!/usr/bin/env bash
# Test whether count alone (with simple skill content) triggers Cowork rejection at 22 skills.
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
OUT_ABS="$(cd "findings/$(verifier_version_dir)" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

build_clones() {
  local label="$1"
  local count="$2"
  local dest="$tmp/$label/verifier-$label"
  mkdir -p "$dest/.claude-plugin" "$dest/hooks"
  cp verifier/.claude-plugin/plugin.json "$dest/.claude-plugin/plugin.json"
  jq --arg n "verifier-$label" '.name=$n' "$dest/.claude-plugin/plugin.json" > "$dest/.claude-plugin/plugin.json.tmp"
  mv "$dest/.claude-plugin/plugin.json.tmp" "$dest/.claude-plugin/plugin.json"
  cp verifier/hooks/hooks.json "$dest/hooks/hooks.json"
  cp verifier/hooks/log.sh verifier/hooks/parallel-{a,b,c}.sh verifier/hooks/block.sh "$dest/hooks/"
  jq 'del(.hooks.UserPromptExpansion)' "$dest/hooks/hooks.json" > "$dest/hooks/hooks.json.tmp"
  mv "$dest/hooks/hooks.json.tmp" "$dest/hooks/hooks.json"
  for i in $(seq -w 1 "$count"); do
    mkdir -p "$dest/skills/clone-$i"
    cat > "$dest/skills/clone-$i/SKILL.md" <<MD
---
name: clone-$i
description: Simple clone $i for count threshold test.
user-invocable: true
---

# clone-$i

Plain text body. Run \`echo clone-$i alive\`.
MD
  done
  ( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
}

build_clones cowork-count-22 22
ls -la "$OUT_ABS/verifier-cowork-count-22.zip"
cp "$OUT_ABS/verifier-cowork-count-22.zip" "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/
ls "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/verifier-cowork-count-22.zip
