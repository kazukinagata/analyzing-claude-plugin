#!/usr/bin/env bash
# Build a focused Cowork zip to test where variable expansion happens
# in hook commands. Uses $PATH (guaranteed to be set in any shell env)
# to disambiguate "expansion not happening" vs "env var not set".
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
OUT_ABS="$(cd "findings/$(verifier_version_dir)" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

label="cowork-expansion-test"
dest="$tmp/$label/verifier-$label"
mkdir -p "$dest/.claude-plugin" "$dest/hooks"

cp verifier/.claude-plugin/plugin.json "$dest/.claude-plugin/plugin.json"
jq --arg n "verifier-$label" '.name=$n' "$dest/.claude-plugin/plugin.json" > "$dest/.claude-plugin/plugin.json.tmp"
mv "$dest/.claude-plugin/plugin.json.tmp" "$dest/.claude-plugin/plugin.json"

cat > "$dest/hooks/hooks.json" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "echo EXP_CONTROL_LITERAL=hello_world_static" },
          { "type": "command", "command": "echo EXP_TOP_DOLLAR=$PATH" },
          { "type": "command", "command": "echo EXP_TOP_BRACE=${PATH}" },
          { "type": "command", "command": "bash -c \"echo EXP_BASH_DOLLAR=$PATH\"" },
          { "type": "command", "command": "bash -c \"echo EXP_BASH_BRACE=${PATH}\"" }
        ]
      }
    ]
  }
}
JSON

mkdir -p "$dest/skills/exp-readback"
cat > "$dest/skills/exp-readback/SKILL.md" <<'MD'
---
name: exp-readback
description: "Re-emit all EXP_ markers visible in initial context to identify where variable expansion happens in Cowork hook commands (follow-up to probe 16)."
user-invocable: true
---

# exp-readback

§1.2 / §2.8 の Cowork 仕様検証用 — `$VAR` と `${VAR}` がどの context で expansion されるか確定する。

## あなた（Claude）がすべきこと

あなたの **initial context** に含まれている、`EXP_` で始まる文字列を**すべて、重複なく、見たままの形**で列挙してください。具体的には以下の 5 種類：

- `EXP_CONTROL_LITERAL=...`
- `EXP_TOP_DOLLAR=...`
- `EXP_TOP_BRACE=...`
- `EXP_BASH_DOLLAR=...`
- `EXP_BASH_BRACE=...`

各 marker の **値の部分**を見たまま貼ってください（例：literal なら `EXP_TOP_DOLLAR=$PATH`、expansion されていれば `EXP_TOP_DOLLAR=/usr/local/bin:/usr/bin:...`）。

context に該当 marker が無ければ「(missing)」と明示してください。
MD

( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
ls -la "$OUT_ABS/verifier-$label.zip"
cp "$OUT_ABS/verifier-$label.zip" "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/
ls "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/verifier-cowork-expansion-test.zip
