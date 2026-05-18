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
  v="$(claude --version 2>/dev/null | awk '{print $1}')"
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
