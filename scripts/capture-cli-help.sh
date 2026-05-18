#!/usr/bin/env bash
# Step 0: Pre-flight check. Capture claude CLI syntax/schema for the current version.
# Run this BEFORE writing any probe-specific logic; the output establishes which
# commands and flags actually exist in v2.1.143.
set -uo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=./_env.sh
. scripts/_env.sh

HELP_DIR="findings/cli-help"
mkdir -p "$HELP_DIR"

run() {
  local label="$1"; shift
  local out="$HELP_DIR/${label}.log"
  printf '$ %s\n' "$*" >"$out"
  "$@" >>"$out" 2>&1
  local rc=$?
  printf '\n(exit=%d)\n' "$rc" >>"$out"
  printf '  %-30s -> %s (exit=%d)\n' "$label" "$out" "$rc"
}

echo "== Step 0a: CLI help ============================================"
run version           claude --version
run root              claude --help
run plugin            claude plugin --help
run marketplace       claude plugin marketplace --help
run install           claude plugin install --help
run uninstall         claude plugin uninstall --help
run validate         claude plugin validate --help

echo
echo "== Step 0b: known-architectural flags ==========================="
# Extract the permission-mode choices line from claude --help.
{
  echo '$ claude --help | grep -A1 -- --permission-mode'
  claude --help 2>&1 | grep -A1 -- '--permission-mode' || true
} >"$HELP_DIR/permission-mode.log"
echo "  permission-mode                -> $HELP_DIR/permission-mode.log"
# Don't actually invoke /plugins via --print; just probe whether --print accepts a no-op prompt.
run print-noop        bash -c 'printf "" | claude --print --help'

echo
echo "== Step 0h: shell baseline ======================================"
{
  echo '$ /bin/sh -c "echo \$0"'
  /bin/sh -c 'echo $0' 2>&1
  echo
  echo '$ ls -l /bin/sh'
  ls -l /bin/sh 2>&1
  echo
  echo '$ /bin/sh -c "echo BASH_VERSION=[\$BASH_VERSION]"'
  /bin/sh -c 'echo BASH_VERSION=[$BASH_VERSION]' 2>&1
  echo
  echo '$ /bin/sh -c "echo RANDOM=[\$RANDOM]"'
  /bin/sh -c 'echo RANDOM=[$RANDOM]' 2>&1
  echo
  echo '$ /bin/sh -c "date +%N"'
  /bin/sh -c 'date +%N' 2>&1
  echo
  echo '$ flock --version'
  flock --version 2>&1
} >"$HELP_DIR/shell-baseline.log"
echo "  shell-baseline                -> $HELP_DIR/shell-baseline.log"

echo
echo "== Step 0 leak baseline marker =================================="
# Marker for detecting writes into ~/.claude after running probes.
LEAK_MARKER="$CLAUDE_CONFIG_DIR/.before-marker"
touch "$LEAK_MARKER"
echo "  marker: $LEAK_MARKER"

cat <<EOF

== Next ==
Read findings/cli-help/STEP0-SUMMARY.md (you'll write this by hand based on the *.log files).
Important things to confirm:

  0a CLI syntax:        plugin / marketplace / install サブコマンドの flags
  0b architectural:     --permission-mode 選択肢、--print の挙動
  0c install only-from-marketplace の文言があるか
  0d marketplace.json schema:  既存例 ~/.claude/plugins/marketplaces/*/.claude-plugin/marketplace.json
  0e --plugin-dir slash namespace:  ephemeral plugin の slash 名前空間 (要・対話起動で確認)
  0f UserPromptExpansion:  hooks.json schema として validator が通すか
  0g SKILL.md frontmatter schema:  user-invocable, hooks, once:true の互換性
  0h shell baseline:    /bin/sh の実体、\$RANDOM, date +%N

これらの結果を STEP0-SUMMARY.md に整理してから各 probe の実装に進む。
EOF
