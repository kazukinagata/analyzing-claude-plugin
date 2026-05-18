#!/usr/bin/env bash
# scripts/install-marketplace.sh — Project-scoped marketplace + plugin install.
#
# Required for probes 02 (substitution-allowlist's violator install error),
# 05 (userconfig-trigger via /plugins UI), 06 (marketplace-cache vs source).
#
# All other probes work with `claude --plugin-dir ./verifier` and do NOT
# need to run this script.
set -uo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=./_env.sh
. scripts/_env.sh

REPO="$(pwd)"
LOG="findings/$(verifier_version_dir)/install.log"
mkdir -p "$(dirname "$LOG")"
exec > >(tee -a "$LOG") 2>&1

echo "== install-marketplace.sh =="
echo "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR"
echo "REPO=$REPO"
echo "Claude Code version: $(claude --version)"
echo

echo "1. claude plugin marketplace add $REPO"
claude plugin marketplace add "$REPO" || true
echo

echo "2. claude plugin marketplace list"
claude plugin marketplace list || true
echo

# Default scope is user; -s local writes to .claude/settings.local.json in cwd.
echo "3. claude plugin install verifier@verifier-mp -s local"
claude plugin install verifier@verifier-mp -s local || true
echo

echo "4. claude plugin install verifier-violator@verifier-mp -s local (EXPECTED TO ERROR for §1.2 violator)"
claude plugin install verifier-violator@verifier-mp -s local || true
echo

echo "5. claude plugin list"
claude plugin list || true
echo

echo "== finished =="
echo "Inspect findings/$(verifier_version_dir)/install.log for the full transcript."
echo "If you want to undo:  claude plugin uninstall verifier@verifier-mp -s local -y"
