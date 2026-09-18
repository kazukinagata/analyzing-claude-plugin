#!/usr/bin/env bash
# scripts/package-subagentstart-ladder2.sh
#
# Ladder 1 (sa-l0..l6) ALL passed the Cowork uploader, yet the real
# cowork-subagentstart-probe failed with "1 error". So the rejected thing is one
# of the differences between l6 and the real probe. This ladder closes that gap,
# one element per rung, ending at a byte-identical copy of the probe.
#
#   l7  +execform   l6 + a SessionStart entry in exec form ("command":"echo","args":[...])
#   l8  +scripts    l7 + the bundled scripts wired into SubagentStart / PostToolUse
#                       (emit-json.sh, emit-matched.sh, replay-log.sh) instead of inline echo
#   l9  +longdesc   l8 + the probe's full-length plugin.json description
#   l10 full        the real probe, renamed only  == the zip that failed
#
# Reading it:
#   l10 PASSES            -> the original failure was transient/stale upload; reinstall the probe.
#   l7 FAILS              -> exec-form hook entries are rejected.
#   l8 FAILS              -> a bundled script wired to SubagentStart/PostToolUse is rejected.
#   l9 FAILS              -> the long plugin.json description is rejected (length or characters).
#   l7..l9 PASS, l10 FAILS -> the long SKILL.md / agent content is rejected.
set -uo pipefail
cd "$(dirname "$0")/.."

command -v zip >/dev/null 2>&1 || { echo "zip not found" >&2; exit 2; }
src=cowork-subagentstart-probe
[ -d "$src" ] || { echo "missing $src" >&2; exit 2; }
out=dist; mkdir -p "$out"
long_desc="$(python3 -c "import json;print(json.load(open('$src/.claude-plugin/plugin.json'))['description'])")"

stage="$(mktemp -d -t sa-ladder2-XXXXXX)"
trap 'rm -rf "$stage"' EXIT

zip_it() {
  local name="$1"
  rm -f "$out/$name.zip"
  ( cd "$stage" && zip -r "$OLDPWD/$out/$name.zip" "$name" -x '*/.DS_Store' >/dev/null )
  echo "  -> $out/$name.zip"
}

build() { # build <rung> <name>
  local rung="$1"
  local name="$2"
  local root="$stage/$name"
  mkdir -p "$root/.claude-plugin" "$root/hooks" "$root/skills/sa-check" "$root/agents"
  cp "$src/agents/sa-reporter.md" "$root/agents/"
  cp "$src/hooks/_lib.sh" "$src/hooks/emit-json.sh" "$src/hooks/emit-matched.sh" "$src/hooks/replay-log.sh" "$root/hooks/"
  chmod +x "$root/hooks"/*.sh

  LONG_DESC="$long_desc" python3 - "$root" "$name" "$rung" <<'PY'
import json, os, sys
root, name, rung = sys.argv[1], sys.argv[2], int(sys.argv[3])

desc = os.environ["LONG_DESC"] if rung >= 9 else (
    "Rung %d of the SubagentStart validation ladder 2." % rung)
json.dump({"name": name, "version": "0.1.0", "description": desc,
           "author": {"name": "kazukinagata"}},
          open(os.path.join(root, ".claude-plugin", "plugin.json"), "w"), indent=2)

S = lambda rel: '"${CLAUDE_PLUGIN_ROOT}/hooks/%s"' % rel
cmd = lambda c: {"type": "command", "command": c}

h = {"SessionStart": [{"matcher": "startup|resume|clear|compact",
                       "hooks": [cmd("echo 'SAL-CTL rung=%d alive'" % rung),
                                 cmd(S("emit-json.sh"))]}]}
if rung >= 7:
    h["SessionStart"][0]["hooks"].append(
        {"type": "command", "command": "echo", "args": ["SAL-CTL exec_form=alive"]})

if rung >= 8:   # real scripts wired to the events under test
    h["PostToolUse"] = [{"matcher": "Agent|Task", "hooks": [cmd(S("replay-log.sh"))]}]
    h["SubagentStart"] = [
        {"hooks": [cmd("echo 'SAL-PLAIN fired'"), cmd(S("emit-json.sh"))]},
        {"matcher": "sa-reporter", "hooks": [cmd(S("emit-matched.sh"))]},
    ]
else:           # same shape as l6: inline echoes only
    h["PostToolUse"] = [{"matcher": "Agent|Task", "hooks": [cmd("echo 'SAL-POSTTOOL fired'")]}]
    h["SubagentStart"] = [
        {"hooks": [cmd("echo 'SAL-PLAIN fired'")]},
        {"matcher": "sa-reporter", "hooks": [cmd("echo 'SAL-MATCHED fired'")]},
    ]
h["SubagentStop"] = [{"hooks": [cmd("echo 'SAL-STOP fired'")]}]
json.dump({"hooks": h}, open(os.path.join(root, "hooks", "hooks.json"), "w"), indent=2)
PY

  cat > "$root/skills/sa-check/SKILL.md" <<MD
---
name: sa-check
description: SubagentStart validation ladder 2, rung ${rung}. Installing this plugin is the test.
user-invocable: true
---

# sa-check (ladder2 rung ${rung})

インストールできたかどうかが結果です。できた場合は context 内の \`SAL-\` 行をそのまま貼ってください。
MD
  zip_it "$name"
}

build 7 sa-l7-execform
build 8 sa-l8-scripts
build 9 sa-l9-longdesc

# l10: the real probe, renamed only
name=sa-l10-full
rm -rf "$stage/$name"; cp -a "$src" "$stage/$name"
python3 - "$stage/$name/.claude-plugin/plugin.json" "$name" <<'PY'
import json, sys
p, n = sys.argv[1], sys.argv[2]
d = json.load(open(p)); d["name"] = n
json.dump(d, open(p, "w"), indent=2)
PY
zip_it "$name"

echo
echo "Try the real probe zip once more FIRST; if it still fails, upload l7 -> l10 in order."
