#!/usr/bin/env bash
# Build a Cowork zip for probe 18 (cross-chat DATA isolation) using
# marker readback strategy. Hooks emit the substituted ${VAR} values
# via bash -c "..." (which we now know expands properly in v2.1.146-148
# Cowork). Skill body emits the same vars from inside the cloud VM bash
# tool. Comparing across chats shows path stability vs rotation.
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
OUT_ABS="$(cd "findings/$(verifier_version_dir)" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

label="cowork-data-isolation"
dest="$tmp/$label/verifier-$label"
mkdir -p "$dest/.claude-plugin" "$dest/hooks"

cp verifier/.claude-plugin/plugin.json "$dest/.claude-plugin/plugin.json"
jq --arg n "verifier-$label" '.name=$n' "$dest/.claude-plugin/plugin.json" > "$dest/.claude-plugin/plugin.json.tmp"
mv "$dest/.claude-plugin/plugin.json.tmp" "$dest/.claude-plugin/plugin.json"

# Use bash -c "..." form because we proved (probe 16 follow-up) that
# top-level echo doesn't expand $VAR / ${VAR} on Cowork.
cat > "$dest/hooks/hooks.json" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "bash -c \"echo HOOK_HOST_ROOT=$CLAUDE_PLUGIN_ROOT\"" },
          { "type": "command", "command": "bash -c \"echo HOOK_HOST_DATA=$CLAUDE_PLUGIN_DATA\"" },
          { "type": "command", "command": "bash -c \"echo HOOK_HOST_REMOTE=$CLAUDE_CODE_REMOTE\"" },
          { "type": "command", "command": "bash -c \"echo HOOK_HOST_HOSTNAME=$(hostname)\"" },
          { "type": "command", "command": "bash -c \"echo HOOK_HOST_SESSIONS_DIR_EXISTS=$([ -d /sessions ] && echo yes || echo no)\"" }
        ]
      }
    ]
  }
}
JSON

mkdir -p "$dest/skills/data-readback"
cat > "$dest/skills/data-readback/SKILL.md" <<'MD'
---
name: data-readback
description: "Echo plugin-level hook host paths from initial context AND echo cloud VM bash subprocess values to compare across chats (probe 18 redesign)."
user-invocable: true
---

# data-readback

§2.11 / §2.12 / §1.1 の v2.1.146-148 検証用。Cowork で:
1. plugin-level hook (= local Claude Desktop で実行) が見ている `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PLUGIN_DATA}` の path 形式と値
2. skill body の Bash tool (= cloud VM で実行) が見ている path / env / hostname
3. 別 chat 間で 1 と 2 がどう変化するか

を一度に取得する。

## ステップ 1: initial context にある HOOK_HOST_* マーカーを列挙

あなた（Claude）の initial context に含まれている、以下の prefix で始まる文字列を**値も含めて、見たままの形で**全部列挙してください：

- `HOOK_HOST_ROOT=...`
- `HOOK_HOST_DATA=...`
- `HOOK_HOST_REMOTE=...`
- `HOOK_HOST_HOSTNAME=...`
- `HOOK_HOST_SESSIONS_DIR_EXISTS=...`

## ステップ 2: cloud VM 側の bash で同じ情報を取得

```bash
echo "BASH_VM_HOSTNAME=$(hostname)"
echo "BASH_VM_CWD=$PWD"
echo "BASH_VM_ROOT=$CLAUDE_PLUGIN_ROOT"
echo "BASH_VM_DATA=$CLAUDE_PLUGIN_DATA"
echo "BASH_VM_REMOTE=$CLAUDE_CODE_REMOTE"
echo "BASH_VM_CODENAME=$(ls /sessions 2>/dev/null | head -1)"
echo "BASH_VM_SUBST_ROOT=${CLAUDE_PLUGIN_ROOT}"
echo "BASH_VM_SUBST_DATA=${CLAUDE_PLUGIN_DATA}"
```

## このスキルを 3 回別の文脈で起動して比較

| 起動文脈 | 期待される観測 |
|---|---|
| (A) 新規 chat 1 回目 | ROOT/DATA path をすべて記録 |
| (B) 別の新規 chat | (A) と比較。DATA は別、ROOT は同じが期待 |
| (C) (A) の chat を window 非アクティブ 3 分以上放置 → 戻ってもう 1 回 invoke | (A) と同じ DATA / 同じ codename が期待 (resume) |

step 1 と step 2 の結果を逐語で（path 全長含めて）貼ってください。
MD

( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
ls -la "$OUT_ABS/verifier-$label.zip"
cp "$OUT_ABS/verifier-$label.zip" "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/
ls "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/verifier-cowork-data-isolation.zip
