#!/usr/bin/env bash
# scripts/package-desc-length-bisect.sh
#
# Ladder 2 localized the Cowork rejection to rung l9 = "the probe's long
# plugin.json description". Known data points (description length -> Cowork):
#
#     430 cowork-exec-form-probe        installed OK
#     431 cowork-userconfig2-probe      installed OK
#     458 cowork-data-persist-probe     installed OK
#     521 cowork-subagentstart-probe    REJECTED (1 error)
#     821 cowork-mcp-tool-hook-probe    REJECTED (earlier probe, same symptom)
#
# So the cutoff sits in (458, 521]. 500 is the obvious suspect. Each zip below is
# byte-identical to the known-good sa-l8-scripts except for the description,
# which is padded to an EXACT character count.
#
#   sa-desc-480   480 chars
#   sa-desc-500   500 chars
#   sa-desc-501   501 chars
#   sa-desc-512   512 chars
#   sa-desc-punct 500 chars including ' ; ( ) : - (char-class control)
#
# Upload sa-desc-500 and sa-desc-501 first:
#   500 PASS, 501 FAIL -> hard limit is 500 characters.
#   both FAIL          -> try 480 (limit is lower).
#   both PASS          -> try 512, then re-check whether length is really the axis.
#   500 FAIL but punct-free 480 PASS while sa-desc-punct FAILS -> characters, not length.
set -uo pipefail
cd "$(dirname "$0")/.."

command -v zip >/dev/null 2>&1 || { echo "zip not found" >&2; exit 2; }
base=dist/sa-l8-scripts.zip
[ -f "$base" ] || { echo "missing $base — run scripts/package-subagentstart-ladder2.sh first" >&2; exit 2; }
out=dist

stage="$(mktemp -d -t sa-desc-XXXXXX)"
trap 'rm -rf "$stage"' EXIT

build() { # build <name> <length> <punct:yes|no>
  local name="$1" len="$2" punct="$3"
  rm -rf "$stage/work"; mkdir -p "$stage/work"
  unzip -q "$base" -d "$stage/work"
  mv "$stage/work/sa-l8-scripts" "$stage/work/$name"

  python3 - "$stage/work/$name/.claude-plugin/plugin.json" "$name" "$len" "$punct" <<'PY'
import json, sys
p, name, n, punct = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
head = ("Description length probe: this plugin is identical to the known-good rung "
        "sa-l8-scripts except that its description is padded to exactly %d characters, "
        "to find the point where the Cowork uploader starts rejecting it" % n)
if punct == "yes":
    head += " (control: includes ' ; ( ) : - so 'characters' can be told from 'length')"
head += ". Padding follows: "
desc = (head + "pad " * n)[:n]
d = json.load(open(p)); d["name"] = name; d["description"] = desc
assert len(d["description"]) == n, len(d["description"])
json.dump(d, open(p, "w"), indent=2)
print("   %-14s desc=%d chars" % (name, n))
PY

  rm -f "$out/$name.zip"
  ( cd "$stage/work" && zip -r "$OLDPWD/$out/$name.zip" "$name" -x '*/.DS_Store' >/dev/null )
}

build sa-desc-480   480 no
build sa-desc-500   500 no
build sa-desc-501   501 no
build sa-desc-512   512 no
build sa-desc-punct 500 yes
echo
echo "Upload sa-desc-500 and sa-desc-501 first."
