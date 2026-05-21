# shellcheck shell=sh
# Source this file before any claude invocation:  . scripts/_env.sh
# Works under bash, dash, and zsh. Sets CLAUDE_CONFIG_DIR to project-local
# findings/claude-home/ so global ~/.claude/ stays untouched.

# Resolve repo root. bash exposes BASH_SOURCE; POSIX sh has no portable way to
# learn the path of a sourced file, so fall back to the current directory and
# walk upward until we find the marketplace manifest.
if [ -n "${BASH_SOURCE:-}" ]; then
  __verifier_self="${BASH_SOURCE:-$0}"
  __VERIFIER_REPO_ROOT="$(cd "$(dirname "$__verifier_self")/.." && pwd)"
else
  __VERIFIER_REPO_ROOT="$PWD"
  while [ "$__VERIFIER_REPO_ROOT" != "/" ] && [ ! -f "$__VERIFIER_REPO_ROOT/.claude-plugin/marketplace.json" ]; do
    __VERIFIER_REPO_ROOT="$(dirname "$__VERIFIER_REPO_ROOT")"
  done
  if [ "$__VERIFIER_REPO_ROOT" = "/" ]; then
    echo "_env.sh: could not locate repo root from \$PWD=$PWD; cd into analyzing-claude-plugin first" >&2
    return 1 2>/dev/null || exit 1
  fi
fi
export CLAUDE_CONFIG_DIR="${__VERIFIER_REPO_ROOT}/findings/claude-home"
mkdir -p "$CLAUDE_CONFIG_DIR"

# Version string used for finding output directory. Resolved lazily so a missing
# claude binary doesn't break sourcing.
verifier_version_dir() {
  v="$(claude --version 2>/dev/null | cut -d' ' -f1)"
  if [ -n "$v" ]; then
    printf 'v%s' "$v"
  else
    printf 'v-unknown'
  fi
}
# bash supports exporting functions; dash doesn't. Skip it under non-bash shells.
if [ -n "${BASH_VERSION:-}" ]; then
  export -f verifier_version_dir 2>/dev/null || true
fi
export VERIFIER_REPO_ROOT="$__VERIFIER_REPO_ROOT"

# Export VERIFIER_VERSION_DIR as a plain env var so child processes (claude,
# Bash tool subprocesses, hooks) can read it without re-running awk/cut.
# Skill body markdown was getting "$1" stripped by Claude Code's pre-
# substitution, which corrupted the version dir name; this avoids that
# entirely.
VERIFIER_VERSION_DIR="$(verifier_version_dir)"
export VERIFIER_VERSION_DIR

# Share Claude account credentials AND startup state with the isolated
# CLAUDE_CONFIG_DIR so `claude --plugin-dir ./verifier` doesn't re-prompt
# for login or replay the first-run welcome flow.
#
# - .credentials.json: OAuth tokens (symlink, so refresh tokens stay in sync)
# - .claude.json: numStartups / onboarding flags / oauthAccount blob (symlink;
#   the isolated home reuses the host's startup state but plugin/settings
#   isolation stays intact because ~/.claude/plugins/ and settings.json live
#   inside CLAUDE_CONFIG_DIR, not at $HOME/.claude.json).
if [ -f "$HOME/.claude/.credentials.json" ] && [ ! -e "$CLAUDE_CONFIG_DIR/.credentials.json" ]; then
  ln -sfn "$HOME/.claude/.credentials.json" "$CLAUDE_CONFIG_DIR/.credentials.json"
fi
if [ -f "$HOME/.claude.json" ]; then
  # If a stub .claude.json was left behind from a previous launch (under ~1KB
  # vs host's 100KB+), replace it with a symlink so the welcome flow stays
  # marked as completed.
  if [ ! -e "$CLAUDE_CONFIG_DIR/.claude.json" ] || [ "$(wc -c <"$CLAUDE_CONFIG_DIR/.claude.json" 2>/dev/null || echo 0)" -lt 2048 ]; then
    rm -f "$CLAUDE_CONFIG_DIR/.claude.json"
    ln -sfn "$HOME/.claude.json" "$CLAUDE_CONFIG_DIR/.claude.json"
  fi
fi
