#!/usr/bin/env bash
# Build a Cowork-only zip where hooks.json = parser test variant (stdout-only).
# Purpose: §2.6 parser whitelist verification on Cowork where file I/O is dead.
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
OUT_ABS="$(cd "findings/$(verifier_version_dir)" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

label="cowork-parser-tests"
dest="$tmp/$label/verifier-$label"
mkdir -p "$dest/.claude-plugin" "$dest/hooks"

# Plugin metadata with renamed plugin to avoid conflict with the main verifier
cp verifier/.claude-plugin/plugin.json "$dest/.claude-plugin/plugin.json"
jq --arg n "verifier-$label" '.name=$n' "$dest/.claude-plugin/plugin.json" > "$dest/.claude-plugin/plugin.json.tmp"
mv "$dest/.claude-plugin/plugin.json.tmp" "$dest/.claude-plugin/plugin.json"

# Use the cowork parser-tests variant as hooks.json
cp verifier/hooks/hooks-parser-tests-cowork.json "$dest/hooks/hooks.json"

# Minimal SKILL to read the test output (Claude's initial context will already have it)
mkdir -p "$dest/skills/14-parser-readback"
cat > "$dest/skills/14-parser-readback/SKILL.md" <<'MD'
---
name: 14-parser-readback
description: "Re-emit any PARSER_TEST markers visible in initial context so we can record which Cowork hook command parser entries survived."
user-invocable: true
---

# 14-parser-readback

§2.6 — Cowork parser whitelist verification, stdout-only variant.

このプラグインを Cowork で enable + 新規 chat を開くと、SessionStart hook 配列が 8 entry 発火します。それぞれ異なる shell construct を test し、stdout に `PARSER_TEST_*` marker を出します。

Cowork は file I/O を sandbox に届けないが、SessionStart hook の **stdout は additionalContext として Claude の初期 context に injection** されるはず。

## このスキルがすべきこと

1. あなた（Claude）の **initial context** に含まれている `PARSER_TEST_` で始まる文字列を**すべて、重複なく**列挙してください。
2. 列挙した結果を、以下の bash でユーザに見える形で出力してください：

```bash
cat <<'EOF'
=== PARSER_TEST markers seen in initial context ===
(ここに列挙: 1 行 1 marker)
=== END ===
EOF
```

3. その後、現在の Cowork session の codename も print してください：

```bash
ls /sessions/ 2>/dev/null
echo "PWD=$PWD"
```

context に何も `PARSER_TEST_*` が無ければ、「(none observed)」と書いてください。
MD

( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
ls -la "$OUT_ABS/verifier-$label.zip"
cp "$OUT_ABS/verifier-$label.zip" "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/
ls "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/verifier-cowork-parser-tests.zip
