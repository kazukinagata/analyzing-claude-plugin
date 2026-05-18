#!/usr/bin/env bash
# scripts/assert-all.sh — Run assert.sh for every probe and aggregate into report.md.
#
# Usage: assert-all.sh

set -uo pipefail

cd "$(dirname "$0")/.."
# shellcheck source=./_env.sh
. scripts/_env.sh

VER="$(verifier_version_dir)"
out_dir="findings/$VER"
mkdir -p "$out_dir"
report="$out_dir/report.md"

# Collect probe IDs from expected/*.txt
probes=()
for f in findings/expected/*.txt; do
  [ -f "$f" ] || continue
  bn="$(basename "$f" .txt)"
  probes+=("$bn")
done

if [ ${#probes[@]} -eq 0 ]; then
  echo "no expected files in findings/expected/" >&2
  exit 1
fi

{
  echo "# Re-verification report — $VER"
  echo
  echo "Generated: $(date -Iseconds)"
  echo "Claude Code: $(claude --version 2>/dev/null)"
  echo
  echo "## verdicts"
  echo
  echo "| probe | verdict | matched | missing | unwanted |"
  echo "|---|---|---|---|---|"
} >"$report"

canary_ok=1
# First pass: determine canary status by running probe 00 explicitly.
canary_raw="$(bash scripts/assert.sh 00 2>&1 || true)"
canary_verdict="$(printf '%s\n' "$canary_raw" | head -1 | sed -n 's/^\[[^]]*\] *\([A-Z][A-Z-]*\).*/\1/p')"
[ "$canary_verdict" = "PASS" ] || canary_ok=0

for probe in "${probes[@]}"; do
  # Run assert.sh, capture summary line.
  raw="$(bash scripts/assert.sh "$probe" 2>&1 || true)"
  summary="$(printf '%s\n' "$raw" | head -1)"
  # Summary format: "[<probe>] <VERDICT>  (matched=N, missing=N, unwanted=N)"
  verdict="$(echo "$summary" | sed -n 's/^\[[^]]*\] *\([A-Z][A-Z-]*\).*/\1/p')"
  [ -z "$verdict" ] && verdict="UNKNOWN"
  matched="$(echo "$summary" | sed -n 's/.*matched=\([0-9]*\).*/\1/p')"
  missing="$(echo "$summary" | sed -n 's/.*missing=\([0-9]*\).*/\1/p')"
  unwanted="$(echo "$summary" | sed -n 's/.*unwanted=\([0-9]*\).*/\1/p')"

  # Cascade CANARY-FAILED to downstream probes when probe 00 didn't pass.
  if [ $canary_ok -eq 0 ] && [[ "$probe" != 00* ]]; then
    verdict="CANARY-FAILED"
  fi

  echo "| $probe | $verdict | ${matched:-0} | ${missing:-0} | ${unwanted:-0} |" >>"$report"
done

{
  echo
  if [ $canary_ok -eq 0 ]; then
    echo "## ⚠ CANARY FAILED"
    echo
    echo "probe 00-canary did not PASS. All subsequent verdicts should be treated as **CANARY-FAILED** regardless of the table above — the observation infrastructure itself is broken in this version."
    echo
  fi
  echo "## verdict meanings"
  echo
  echo "- **PASS** — finding still holds (log matches expected)"
  echo "- **FAIL** — finding has changed (alive-check present but expected pattern missing)"
  echo "- **PARTIAL** — some subclaims match, some don't"
  echo "- **UNKNOWN** — observation failed (alive-check missing, can't tell if finding changed)"
  echo "- **DOC-ALIGNED** — finding changed in a direction that aligns with docs (bug fixed)"
  echo "- **CANARY-FAILED** — observation infrastructure broken; probe 00 must PASS first"
  echo "- **MANUAL-OK / MANUAL-NG** — auto judgment not possible; human review required"
} >>"$report"

echo "report -> $report"
cat "$report"
