#!/usr/bin/env bash
# Build only the latest narrowing zips (min33+) — does NOT touch existing zips on Desktop.
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
OUT_ABS="$(cd "findings/$(verifier_version_dir)" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

build_03_fm() {
  local label="$1"
  local fm_command="$2"
  local dest="$tmp/$label/verifier-$label"
  mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/hello-fm" "$dest/skills/00-canary" "$dest/skills/03-shell-binsh"
  # baseline plugin.json
  cat > "$dest/.claude-plugin/plugin.json" <<JSON
{
  "name": "verifier-$label",
  "version": "0.1.0",
  "description": "narrowing $label",
  "author": { "name": "kazukinagata" },
  "userConfig": {
    "hello_message": { "type": "string", "title": "Hello", "description": "non-sensitive" },
    "api_secret":    { "type": "string", "title": "Secret", "description": "sensitive", "sensitive": true }
  }
}
JSON
  # full plugin-level hooks like min5
  cp verifier/hooks/hooks.json "$dest/hooks/hooks.json"
  cp verifier/hooks/log.sh "$dest/hooks/log.sh"
  cp verifier/hooks/parallel-{a,b,c}.sh "$dest/hooks/"
  cp verifier/hooks/block.sh "$dest/hooks/block.sh"
  jq 'del(.hooks.UserPromptExpansion)' "$dest/hooks/hooks.json" > "$dest/hooks/hooks.json.tmp"
  mv "$dest/hooks/hooks.json.tmp" "$dest/hooks/hooks.json"
  # hello-fm (simple frontmatter pretool:bash skill)
  cat > "$dest/skills/hello-fm/SKILL.md" <<'MD'
---
name: hello-fm
description: A user-invocable skill with a frontmatter PreToolUse:Bash hook.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'echo "[hello-fm] PreToolUse:Bash hook fired"'
---

# hello-fm
MD
  # 00-canary real
  cp -r verifier/skills/00-canary "$dest/skills/"
  # 03 stub body with the FM command we're testing
  cat > "$dest/skills/03-shell-binsh/SKILL.md" <<MD
---
name: 03-shell-binsh
description: Narrowing — frontmatter command varies, body minimal.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: '$fm_command'
---

# 03 stub ($label)

\`\`\`bash
echo "stub body"
\`\`\`
MD
  ( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
}

# min33: brace group { } with command substitution and printf-style format
# Same shape as 03's frontmatter but without ${PWD^^}, without redirect, without ; exit 0
build_03_fm min33-fm-brace-only '{ printf "[03 %s]\n" "$(date -Iseconds)"; }'

# min34: brace + 2>&1
build_03_fm min34-fm-brace-2_to_1 '{ printf "[03 %s]\n" "$(date -Iseconds)" 2>&1; }'

# min35: brace + redirect to a path with multiple ${...} substitutions
build_03_fm min35-fm-brace-redirect '{ printf "[03 %s]\n" "$(date -Iseconds)"; } >> "$CLAUDE_PROJECT_DIR/findings/${VERIFIER_VERSION_DIR:-v-unknown}/${CLAUDE_SESSION_ID:-no-sid}/probe.log"'

# min36: full 03-style command MINUS ${PWD^^} (was already done as min22; rebuild fresh after closing-quote fix to confirm)
build_03_fm min36-fm-real-no-pwd '{ printf "[03-FM-bashisms %s] BASH_VERSION=[%s] uppercased=[PWD_PLACEHOLDER]\n" "$(date -Iseconds)" "$BASH_VERSION" 2>&1; } >> "$CLAUDE_PROJECT_DIR/findings/${VERIFIER_VERSION_DIR:-v-unknown}/${CLAUDE_SESSION_ID:-no-sid}/probe.log" 2>&1 ; exit 0'

# Copy only the new zips
NEW_ZIPS=("$OUT_ABS/verifier-min33-fm-brace-only.zip" "$OUT_ABS/verifier-min34-fm-brace-2_to_1.zip" "$OUT_ABS/verifier-min35-fm-brace-redirect.zip" "$OUT_ABS/verifier-min36-fm-real-no-pwd.zip")
cp "${NEW_ZIPS[@]}" /mnt/c/Users/knaga/OneDrive/Desktop/
for z in "${NEW_ZIPS[@]}"; do
  ls -la "$z"
done
echo "---copied to desktop:---"
ls /mnt/c/Users/knaga/OneDrive/Desktop/verifier-min3[3-6]*.zip
