#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
OUT_ABS="$(cd "findings/$(verifier_version_dir)" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

build_17_variant() {
  local label="$1"
  local skill_content_file="$2"
  local dest="$tmp/$label/verifier-$label"
  mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/17-cowork-bash-mount"
  cp verifier/.claude-plugin/plugin.json "$dest/.claude-plugin/plugin.json"
  jq --arg n "verifier-$label" '.name=$n' "$dest/.claude-plugin/plugin.json" > "$dest/.claude-plugin/plugin.json.tmp"
  mv "$dest/.claude-plugin/plugin.json.tmp" "$dest/.claude-plugin/plugin.json"
  cp verifier/hooks/hooks.json "$dest/hooks/hooks.json"
  cp verifier/hooks/log.sh verifier/hooks/parallel-{a,b,c}.sh verifier/hooks/block.sh "$dest/hooks/"
  jq 'del(.hooks.UserPromptExpansion)' "$dest/hooks/hooks.json" > "$dest/hooks/hooks.json.tmp"
  mv "$dest/hooks/hooks.json.tmp" "$dest/hooks/hooks.json"
  cp "$skill_content_file" "$dest/skills/17-cowork-bash-mount/SKILL.md"
  cp -r verifier/skills/17-cowork-bash-mount/scripts "$dest/skills/17-cowork-bash-mount/scripts"
  ( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
}

# Variant 1: 17 with simplified description (no ${...} marker, no angle brackets)
mkdir -p "$tmp/skills17"
cat > "$tmp/skills17/v1.md" <<'MD'
---
name: 17-cowork-bash-mount
description: "Cowork mounts the plugin install dir under sessions filesystem read-only. Bundled scripts can be launched via relative path; CLAUDE_SKILL_DIR expands to a Windows path that fails directly. CLI baseline lets both patterns work (research section 2.10)."
user-invocable: true
---

# 17-cowork-bash-mount

Body unchanged. See verifier/skills/17-cowork-bash-mount/SKILL.md for original.

```bash
echo "stub body"
```
MD
build_17_variant cowork-test17-v1-simple-desc "$tmp/skills17/v1.md"

# Variant 2: same as v1 but include the full original body
cat > "$tmp/skills17/v2.md" <<'MD'
---
name: 17-cowork-bash-mount
description: "Cowork mounts the plugin install dir under sessions filesystem read-only. Bundled scripts can be launched via relative path. CLI baseline lets both patterns work."
user-invocable: true
---

MD
# Append the original body (everything after the first --- closing line)
python3 - "$tmp/skills17/v2.md" verifier/skills/17-cowork-bash-mount/SKILL.md <<'PY'
import sys, re
v2 = sys.argv[1]
orig = sys.argv[2]
src = open(orig).read()
m = re.match(r'^(---\n)(.*?\n)(---\n)(.*)$', src, re.DOTALL)
body = m.group(4)
open(v2, 'a').write(body)
PY
build_17_variant cowork-test17-v2-real-body "$tmp/skills17/v2.md"

ls -la "$OUT_ABS"/verifier-cowork-test17-v{1,2}*.zip
cp "$OUT_ABS"/verifier-cowork-test17-v{1,2}*.zip /mnt/c/Users/knaga/OneDrive/Desktop/
ls /mnt/c/Users/knaga/OneDrive/Desktop/verifier-cowork-test17-v*.zip
