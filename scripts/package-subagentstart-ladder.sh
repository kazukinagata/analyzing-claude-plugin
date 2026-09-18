#!/usr/bin/env bash
# scripts/package-subagentstart-ladder.sh
#
# cowork-subagentstart-probe was rejected by the Cowork uploader with
# "Plugin failed validation with 1 error" and no detail. This builds a CUMULATIVE
# ladder: every rung is the previous rung plus exactly ONE new element, so the
# first rung that fails names the rejected feature.
#
#   L0 baseline   plugin.json + skill + SessionStart shell-form echo   -> should PASS
#   L1 +agent     L0 + agents/sa-reporter.md
#   L2 +script    L1 + "${CLAUDE_PLUGIN_ROOT}/hooks/emit-json.sh" on SessionStart
#   L3 +posttool  L2 + PostToolUse with matcher "Agent|Task"
#   L4 +substop   L3 + SubagentStop hook
#   L5 +substart  L4 + SubagentStart hook (matcher-less)
#   L6 +matcher   L5 + SubagentStart hook with matcher "sa-reporter"  == full probe
#
# Suggested upload order (2 uploads usually settle it):
#   upload L4 and L5 first.
#     L4 PASS, L5 FAIL -> the SubagentStart EVENT is what Cowork rejects.
#     L4 FAIL          -> walk down L0..L3 to find the real culprit.
#     both PASS        -> upload L6; if it fails the MATCHER on SubagentStart is it.
set -uo pipefail
cd "$(dirname "$0")/.."

command -v zip >/dev/null 2>&1 || { echo "zip not found" >&2; exit 2; }
src=cowork-subagentstart-probe
[ -d "$src" ] || { echo "missing $src" >&2; exit 2; }
out=dist; mkdir -p "$out"

stage="$(mktemp -d -t sa-ladder-XXXXXX)"
trap 'rm -rf "$stage"' EXIT

build() { # build <rung-number> <name>
  local rung="$1"
  local name="$2"
  local root="$stage/$name"
  mkdir -p "$root/.claude-plugin" "$root/hooks" "$root/skills/sa-check"

  python3 - "$root" "$name" "$rung" <<'PY'
import json, sys, os
root, name, rung = sys.argv[1], sys.argv[2], int(sys.argv[3])

json.dump({
    "name": name,
    "version": "0.1.0",
    "description": "Rung %d of the SubagentStart validation ladder. Each rung adds exactly one element on top of the previous one; the first rung the Cowork uploader rejects names the offending feature." % rung,
    "author": {"name": "kazukinagata"},
}, open(os.path.join(root, ".claude-plugin", "plugin.json"), "w"), indent=2)

h = {"SessionStart": [{
    "matcher": "startup|resume|clear|compact",
    "hooks": [{"type": "command", "command": "echo 'SAL-CTL rung=%d alive'" % rung}],
}]}
if rung >= 2:
    h["SessionStart"][0]["hooks"].append(
        {"type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/emit-json.sh\""})
if rung >= 3:
    h["PostToolUse"] = [{"matcher": "Agent|Task", "hooks": [
        {"type": "command", "command": "echo 'SAL-POSTTOOL fired'"}]}]
if rung >= 4:
    h["SubagentStop"] = [{"hooks": [
        {"type": "command", "command": "echo 'SAL-STOP fired'"}]}]
if rung >= 5:
    h["SubagentStart"] = [{"hooks": [
        {"type": "command", "command": "echo 'SAL-PLAIN fired'"}]}]
if rung >= 6:
    h["SubagentStart"].append({"matcher": "sa-reporter", "hooks": [
        {"type": "command", "command": "echo 'SAL-MATCHED fired'"}]})
json.dump({"hooks": h}, open(os.path.join(root, "hooks", "hooks.json"), "w"), indent=2)
PY

  cat > "$root/skills/sa-check/SKILL.md" <<MD
---
name: sa-check
description: SubagentStart validation ladder rung ${rung}. Installing this plugin is the test; invoking the skill just prints the markers that reached context.
user-invocable: true
---

# sa-check (ladder rung ${rung})

この plugin が **インストールできたかどうか**が結果です。インストールできた場合は、
context 内の \`SAL-\` で始まる行をそのまま貼ってください（無ければ「無し」）。
MD

  if [ "$rung" -ge 1 ]; then
    mkdir -p "$root/agents"
    cp "$src/agents/sa-reporter.md" "$root/agents/sa-reporter.md"
  fi
  if [ "$rung" -ge 2 ]; then
    cp "$src/hooks/_lib.sh" "$src/hooks/emit-json.sh" "$root/hooks/"
    chmod +x "$root/hooks"/*.sh
  fi

  rm -f "$out/$name.zip"
  ( cd "$stage" && zip -r "$OLDPWD/$out/$name.zip" "$name" -x '*/.DS_Store' >/dev/null )
  echo "  -> $out/$name.zip"
}

build 0 sa-l0-baseline
build 1 sa-l1-agent
build 2 sa-l2-script
build 3 sa-l3-posttool
build 4 sa-l4-substop
build 5 sa-l5-substart
build 6 sa-l6-matcher
echo
echo "Upload L4 and L5 first; see the header of this script for how to read the result."
