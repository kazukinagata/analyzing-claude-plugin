#!/usr/bin/env bash
# Re-bisect Cowork-rejectable skills (knowing 03 is one of them).
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
OUT_ABS="$(cd "findings/$(verifier_version_dir)" && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

build_subset() {
  local label="$1"; shift
  local skill_dirs=("$@")
  local dest="$tmp/$label/verifier-$label"
  mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills"
  # copy full plugin metadata + hooks
  cp verifier/.claude-plugin/plugin.json "$dest/.claude-plugin/plugin.json"
  # rename plugin name to avoid conflict (jq for safety)
  jq --arg n "verifier-$label" '.name=$n' "$dest/.claude-plugin/plugin.json" > "$dest/.claude-plugin/plugin.json.tmp"
  mv "$dest/.claude-plugin/plugin.json.tmp" "$dest/.claude-plugin/plugin.json"
  cp verifier/hooks/hooks.json "$dest/hooks/hooks.json"
  cp verifier/hooks/log.sh verifier/hooks/parallel-{a,b,c}.sh verifier/hooks/block.sh "$dest/hooks/"
  jq 'del(.hooks.UserPromptExpansion)' "$dest/hooks/hooks.json" > "$dest/hooks/hooks.json.tmp"
  mv "$dest/hooks/hooks.json.tmp" "$dest/hooks/hooks.json"
  for s in "${skill_dirs[@]}"; do
    cp -r "verifier/skills/$s" "$dest/skills/$s"
  done
  ( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
  echo "$OUT_ABS/verifier-$label.zip"
}

FIRST_HALF_NO_03=(00-canary 01-env-propagation 02-substitution-allowlist 04-sensitive-leak 05-userconfig-trigger 06-marketplace-cache 07-skill-body-subst 08-frontmatter-timing 08b-self-block-attempt 09-slash-vs-natural)
SECOND_HALF=(10-parallel-hook-firing 11-block-target 12-block-self 13-cowork-pretooluse 14-cowork-parser 15-cowork-file-io 16-cowork-path-forms 17-cowork-bash-mount 18-cowork-data-isolation 19-cowork-resume 20-cowork-validation 21-cowork-connected-folder)

FIRST_NO_SUSPECTS=(00-canary 01-env-propagation 02-substitution-allowlist 04-sensitive-leak 05-userconfig-trigger 06-marketplace-cache 07-skill-body-subst 09-slash-vs-natural)
SECOND_NO_SUSPECTS=(10-parallel-hook-firing 11-block-target 13-cowork-pretooluse 14-cowork-parser 15-cowork-file-io 16-cowork-path-forms 17-cowork-bash-mount 18-cowork-data-isolation 19-cowork-resume 20-cowork-validation 21-cowork-connected-folder)

Z3=$(build_subset cowork-bisect-c-first-no-suspects "${FIRST_NO_SUSPECTS[@]}")
Z4=$(build_subset cowork-bisect-d-second-no-suspects "${SECOND_NO_SUSPECTS[@]}")

ls -la "$Z3" "$Z4"
cp "$Z3" "$Z4" "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/
ls "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/verifier-cowork-bisect-C*.zip "${COWORK_OUT_DIR:-/tmp/cowork-zips}"/verifier-cowork-bisect-D*.zip
