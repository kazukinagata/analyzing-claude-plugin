#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
OUT_ABS="$(cd "findings/$(verifier_version_dir)" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

build_17_desc() {
  local label="$1"
  local desc="$2"
  local dest="$tmp/$label/verifier-$label"
  mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/17-cowork-bash-mount"
  cp verifier/.claude-plugin/plugin.json "$dest/.claude-plugin/plugin.json"
  jq --arg n "verifier-$label" '.name=$n' "$dest/.claude-plugin/plugin.json" > "$dest/.claude-plugin/plugin.json.tmp"
  mv "$dest/.claude-plugin/plugin.json.tmp" "$dest/.claude-plugin/plugin.json"
  cp verifier/hooks/hooks.json "$dest/hooks/hooks.json"
  cp verifier/hooks/log.sh verifier/hooks/parallel-{a,b,c}.sh verifier/hooks/block.sh "$dest/hooks/"
  jq 'del(.hooks.UserPromptExpansion)' "$dest/hooks/hooks.json" > "$dest/hooks/hooks.json.tmp"
  mv "$dest/hooks/hooks.json.tmp" "$dest/hooks/hooks.json"
  cat > "$dest/skills/17-cowork-bash-mount/SKILL.md" <<MD
---
name: 17-cowork-bash-mount
description: "$desc"
user-invocable: true
---

# 17 stub ($label)

\`\`\`bash
echo "stub body"
\`\`\`
MD
  ( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
}

# Test 1: only ${CLAUDE_SKILL_DIR} marker present
build_17_desc cowork-desc-skilldir 'Description with CLAUDE_SKILL_DIR marker like \${CLAUDE_SKILL_DIR} expands somewhere.'
# Test 2: only <codename> angle brackets present
build_17_desc cowork-desc-angles 'Description with angle brackets like /sessions/<codename>/mnt/ in path.'
# Test 3: both
build_17_desc cowork-desc-both 'Description with both \${CLAUDE_SKILL_DIR} and /sessions/<codename>/ patterns.'

ls -la "$OUT_ABS"/verifier-cowork-desc-*.zip
cp "$OUT_ABS"/verifier-cowork-desc-*.zip "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/
ls "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/verifier-cowork-desc-*.zip
