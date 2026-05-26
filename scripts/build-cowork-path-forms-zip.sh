#!/usr/bin/env bash
# Build a focused Cowork zip to observe HOOK_SUBST and HOOK_ENV path forms.
# These are the 2 of 3 path forms in §2.8 we couldn't see in the regular
# probe 16 run (frontmatter matcher mismatch with mcp__workspace__bash).
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
OUT_ABS="$(cd "findings/$(verifier_version_dir)" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

label="cowork-path-forms"
dest="$tmp/$label/verifier-$label"
mkdir -p "$dest/.claude-plugin" "$dest/hooks"

cp verifier/.claude-plugin/plugin.json "$dest/.claude-plugin/plugin.json"
jq --arg n "verifier-$label" '.name=$n' "$dest/.claude-plugin/plugin.json" > "$dest/.claude-plugin/plugin.json.tmp"
mv "$dest/.claude-plugin/plugin.json.tmp" "$dest/.claude-plugin/plugin.json"

# hooks.json with stdout-only path-form observation hooks
# - HOOK_SUBST_*: uses ${VAR} -> Claude Code pre-substitution (MSYS form expected)
# - HOOK_ENV_*: uses $VAR (no braces) -> /bin/sh env expansion (Linux mount form expected)
cat > "$dest/hooks/hooks.json" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "echo HOOK_SUBST_ROOT=${CLAUDE_PLUGIN_ROOT}" },
          { "type": "command", "command": "echo HOOK_SUBST_DATA=${CLAUDE_PLUGIN_DATA}" },
          { "type": "command", "command": "echo HOOK_ENV_ROOT=$CLAUDE_PLUGIN_ROOT" },
          { "type": "command", "command": "echo HOOK_ENV_DATA=$CLAUDE_PLUGIN_DATA" }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          { "type": "command", "command": "echo HOOK_START_SUBST_ROOT=${CLAUDE_PLUGIN_ROOT}" },
          { "type": "command", "command": "echo HOOK_START_ENV_ROOT=$CLAUDE_PLUGIN_ROOT" }
        ]
      }
    ]
  }
}
JSON

# Minimal skill that asks Claude to relay what it sees in context
mkdir -p "$dest/skills/16-path-readback"
cat > "$dest/skills/16-path-readback/SKILL.md" <<'MD'
---
name: 16-path-readback
description: "Re-emit any HOOK_SUBST/HOOK_ENV markers visible in initial context to observe Cowork path-form trinity (research section 2.8)."
user-invocable: true
---

# 16-path-readback

§2.8 — Cowork path 3 形式観測（hook command substitution / hook env / skill body substitution）の hook 側 2 形式を測定するための専用 skill。

## このスキルがすべきこと

1. あなた（Claude）の initial context（system prompt や additionalContext）に含まれている、以下の prefix で始まる文字列を**すべて、重複なく、見たままの形**で列挙してください：
   - `HOOK_SUBST_ROOT=`
   - `HOOK_SUBST_DATA=`
   - `HOOK_ENV_ROOT=`
   - `HOOK_ENV_DATA=`
   - `HOOK_START_SUBST_ROOT=`
   - `HOOK_START_ENV_ROOT=`

2. 加えて、以下の bash を 1 回だけ実行して skill body substitution の形式も取得してください：

```bash
echo "BODY_SUBST_ROOT=${CLAUDE_PLUGIN_ROOT}"
echo "BODY_SUBST_DATA=${CLAUDE_PLUGIN_DATA}"
echo "BODY_ENV_ROOT=$CLAUDE_PLUGIN_ROOT (in bash sandbox)"
echo "BODY_ENV_DATA=$CLAUDE_PLUGIN_DATA (in bash sandbox)"
```

これで 6 種類（HOOK_SUBST_ROOT/DATA, HOOK_ENV_ROOT/DATA, HOOK_START_SUBST_ROOT, HOOK_START_ENV_ROOT, BODY_SUBST_ROOT/DATA, BODY_ENV_ROOT/DATA）の path 形式が観測できる。

context に該当 marker が無ければ「(none)」と明示してください。
MD

( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
ls -la "$OUT_ABS/verifier-$label.zip"
cp "$OUT_ABS/verifier-$label.zip" "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/
ls "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/verifier-cowork-path-forms.zip
