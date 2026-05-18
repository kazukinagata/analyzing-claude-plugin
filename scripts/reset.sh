#!/usr/bin/env bash
# scripts/reset.sh — Clean findings/ outputs.
#
# Modes:
#   reset.sh                — default: clear current-version findings + cli-help
#   reset.sh --claude-home-only
#   reset.sh --all          — wipe every findings/v*/ plus claude-home
set -uo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=./_env.sh
. scripts/_env.sh
VER="$(verifier_version_dir)"

mode="${1:-current}"
case "$mode" in
  current)
    echo "rm -rf findings/$VER/ findings/cli-help/"
    rm -rf "findings/$VER" findings/cli-help
    ;;
  --claude-home-only)
    echo "rm -rf findings/claude-home/"
    rm -rf findings/claude-home
    ;;
  --all)
    echo "rm -rf findings/v*/ findings/claude-home/ findings/cli-help/"
    rm -rf findings/v* findings/claude-home findings/cli-help
    ;;
  *)
    echo "usage: reset.sh [current|--claude-home-only|--all]" >&2
    exit 1
    ;;
esac
echo "done."
