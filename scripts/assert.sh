#!/usr/bin/env bash
# scripts/assert.sh — Evaluate a probe's logs against findings/expected/<probe-id>.txt
#
# Usage: assert.sh <probe-id>
#   probe-id — e.g. "00", "00-canary", "01", "01-env-propagation"
#              (matches by prefix against findings/expected/*.txt)
#
# Reads:  findings/expected/<probe-id>.txt
# Logs:   findings/v<VER>/<sid>/{hooks.log,probe.log,install.log}  (any matching sid)
#
# Output: verdict line to stdout (PASS / FAIL / PARTIAL / UNKNOWN / DOC-ALIGNED / CANARY-FAILED / MANUAL-OK)
# Exit code: 0 for PASS / DOC-ALIGNED / MANUAL-OK, 1 otherwise.

set -uo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=./_env.sh
. scripts/_env.sh

probe="${1:-}"
if [ -z "$probe" ]; then
  echo "usage: assert.sh <probe-id>" >&2
  exit 2
fi

VER="$(verifier_version_dir)"

# Resolve expected file: try exact match, then prefix match.
expected_file=""
if [ -f "findings/expected/${probe}.txt" ]; then
  expected_file="findings/expected/${probe}.txt"
else
  # Prefix match (e.g. "00" → "00-canary.txt")
  for f in findings/expected/${probe}-*.txt; do
    if [ -f "$f" ]; then
      expected_file="$f"
      break
    fi
  done
fi

if [ -z "$expected_file" ]; then
  echo "[$probe] UNKNOWN — no expected file findings/expected/${probe}*.txt" >&2
  exit 1
fi

# Find log files from all sessions of the current version.
out_dir="findings/$VER"
if [ ! -d "$out_dir" ]; then
  echo "[$probe] UNKNOWN — no findings/$VER/ directory (run the probe first)" >&2
  exit 1
fi

# Concatenate all session logs by category so grep can scan them.
declare -A LOG_CACHE
for category in hooks.log probe.log install.log cli-help.log; do
  buf=""
  while IFS= read -r -d '' f; do
    buf+="$(cat "$f")"$'\n'
  done < <(find "$out_dir" -name "$category" -print0 2>/dev/null)
  LOG_CACHE["$category"]="$buf"
done

# Parse expected file. Section selectors are @<filename>; following lines are
# patterns that must appear (or, if prefixed with !, must NOT appear).
current_section=""
pass_count=0
fail_count=0
missing=()
unwanted=()

while IFS= read -r line; do
  # Strip leading/trailing whitespace
  line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  # Skip blanks and comments
  case "$line" in
    "" | \#*) continue ;;
    @*)
      current_section="${line#@}"
      continue
      ;;
  esac

  if [ -z "$current_section" ]; then
    echo "[$probe] expected file has pattern before any @section: $line" >&2
    continue
  fi

  buf="${LOG_CACHE[$current_section]:-}"
  case "$line" in
    !*)
      pattern="${line#!}"
      # NOTE: `<<<` here-string avoids the pipefail+SIGPIPE trap where
      # `grep -q` exits early on match and printf's SIGPIPE exit (141)
      # becomes the pipeline status under `set -o pipefail`, making
      # every successful match look like a MISS.
      if grep -qF -- "$pattern" <<< "$buf"; then
        unwanted+=("[$current_section] $pattern")
        fail_count=$((fail_count + 1))
      else
        pass_count=$((pass_count + 1))
      fi
      ;;
    *)
      if grep -qF -- "$line" <<< "$buf"; then
        pass_count=$((pass_count + 1))
      else
        missing+=("[$current_section] $line")
        fail_count=$((fail_count + 1))
      fi
      ;;
  esac
done < "$expected_file"

# Determine verdict.
verdict="UNKNOWN"
if [ "$fail_count" -eq 0 ] && [ "$pass_count" -gt 0 ]; then
  verdict="PASS"
elif [ "$pass_count" -eq 0 ] && [ "$fail_count" -gt 0 ]; then
  # If even alive-check is missing, this is observation failure not finding change.
  combined="${LOG_CACHE[probe.log]:-}${LOG_CACHE[hooks.log]:-}"
  if grep -qF "tag=alive-check" <<< "$combined"; then
    verdict="FAIL"
  else
    verdict="UNKNOWN"
  fi
elif [ "$fail_count" -gt 0 ]; then
  verdict="PARTIAL"
fi

# Probe 00 has special status: failure cascades to CANARY-FAILED for later probes.
case "$probe" in
  00*) [ "$verdict" != "PASS" ] && verdict="CANARY-FAILED" ;;
esac

# Probe 06 emits VERDICT=PASS or VERDICT=DOC-ALIGNED directly in probe.log;
# surface that hint regardless of the expected-pattern match.
case "$probe" in
  06*)
    buf="${LOG_CACHE[probe.log]:-}"
    if grep -qF "VERDICT=DOC-ALIGNED" <<< "$buf"; then
      verdict="DOC-ALIGNED"
    elif grep -qF "VERDICT=PASS" <<< "$buf" && [ "$verdict" != "UNKNOWN" ]; then
      verdict="PASS"
    fi
    ;;
esac

echo "[$probe] $verdict  (matched=$pass_count, missing=${#missing[@]}, unwanted=${#unwanted[@]})"
if [ "${#missing[@]}" -gt 0 ]; then
  echo "  Missing:"
  printf '    %s\n' "${missing[@]}"
fi
if [ "${#unwanted[@]}" -gt 0 ]; then
  echo "  Unwanted (found but shouldn't be):"
  printf '    %s\n' "${unwanted[@]}"
fi

case "$verdict" in
  PASS | DOC-ALIGNED | MANUAL-OK | MANUAL_OK) exit 0 ;;
  *) exit 1 ;;
esac
