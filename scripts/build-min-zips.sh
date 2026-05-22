#!/usr/bin/env bash
# Build incremental minimal verifier zips for Cowork rejection narrowing.
# Outputs to findings/v$(claude --version | cut -d' ' -f1)/verifier-min{1,2,3}.zip
# and copies them to the user's Windows desktop.
set -uo pipefail
cd "$(dirname "$0")/.."
. scripts/_env.sh
out_dir="findings/$(verifier_version_dir)"
mkdir -p "$out_dir"
OUT_ABS="$(cd "$out_dir" && pwd)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# --- min1: plugin.json only ---
mkdir -p "$tmp/min1/verifier-min1/.claude-plugin"
cat > "$tmp/min1/verifier-min1/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "verifier-min1",
  "version": "0.1.0",
  "description": "minimal: plugin.json only",
  "author": { "name": "kazukinagata" }
}
JSON
( cd "$tmp/min1" && zip -r "${OUT_ABS}/verifier-min1.zip" verifier-min1 >/dev/null )

# --- min2: + basic SessionStart hook ---
mkdir -p "$tmp/min2/verifier-min2/.claude-plugin" "$tmp/min2/verifier-min2/hooks"
cat > "$tmp/min2/verifier-min2/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "verifier-min2",
  "version": "0.1.0",
  "description": "minimal: + basic SessionStart hook",
  "author": { "name": "kazukinagata" }
}
JSON
cat > "$tmp/min2/verifier-min2/hooks/hooks.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          { "type": "command", "command": "echo verifier-min2 session-start" }
        ]
      }
    ]
  }
}
JSON
( cd "$tmp/min2" && zip -r "${OUT_ABS}/verifier-min2.zip" verifier-min2 >/dev/null )

# --- min3: + user-invocable skill with NO frontmatter hooks ---
mkdir -p "$tmp/min3/verifier-min3/.claude-plugin" "$tmp/min3/verifier-min3/hooks" "$tmp/min3/verifier-min3/skills/hello"
cat > "$tmp/min3/verifier-min3/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "verifier-min3",
  "version": "0.1.0",
  "description": "minimal: + 1 user-invocable skill (no frontmatter hooks)",
  "author": { "name": "kazukinagata" }
}
JSON
cat > "$tmp/min3/verifier-min3/hooks/hooks.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          { "type": "command", "command": "echo verifier-min3 session-start" }
        ]
      }
    ]
  }
}
JSON
cat > "$tmp/min3/verifier-min3/skills/hello/SKILL.md" <<'MD'
---
name: hello
description: A minimal user-invocable skill with no frontmatter hooks.
user-invocable: true
---

# hello

Minimal no-frontmatter-hooks skill. Run `echo hello world from cowork`.
MD
( cd "$tmp/min3" && zip -r "${OUT_ABS}/verifier-min3.zip" verifier-min3 >/dev/null )

# --- min4: min3 + userConfig (hello_message + api_secret) ---
mkdir -p "$tmp/min4/verifier-min4/.claude-plugin" "$tmp/min4/verifier-min4/hooks" "$tmp/min4/verifier-min4/skills/hello"
cat > "$tmp/min4/verifier-min4/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "verifier-min4",
  "version": "0.1.0",
  "description": "min3 + userConfig",
  "author": { "name": "kazukinagata" },
  "userConfig": {
    "hello_message": { "type": "string", "title": "Hello", "description": "non-sensitive probe value" },
    "api_secret":    { "type": "string", "title": "Secret", "description": "sensitive value", "sensitive": true }
  }
}
JSON
cp "$tmp/min3/verifier-min3/hooks/hooks.json" "$tmp/min4/verifier-min4/hooks/hooks.json"
cp "$tmp/min3/verifier-min3/skills/hello/SKILL.md" "$tmp/min4/verifier-min4/skills/hello/SKILL.md"
( cd "$tmp/min4" && zip -r "${OUT_ABS}/verifier-min4.zip" verifier-min4 >/dev/null )

# --- min5: min4 + full plugin-level hooks.json from real verifier (parallel-a/b/c + UserPromptSubmit + PreToolUse Bash/Skill/mcp__workspace__bash + log.sh) ---
mkdir -p "$tmp/min5/verifier-min5/.claude-plugin" "$tmp/min5/verifier-min5/hooks" "$tmp/min5/verifier-min5/skills/hello"
cp "$tmp/min4/verifier-min4/.claude-plugin/plugin.json" "$tmp/min5/verifier-min5/.claude-plugin/plugin.json"
# point name back to min5
sed -i 's/"verifier-min4"/"verifier-min5"/g' "$tmp/min5/verifier-min5/.claude-plugin/plugin.json"
sed -i 's/min3 + userConfig/min4 + full plugin-level hooks/' "$tmp/min5/verifier-min5/.claude-plugin/plugin.json"
cp verifier/hooks/hooks.json "$tmp/min5/verifier-min5/hooks/hooks.json"
cp verifier/hooks/log.sh "$tmp/min5/verifier-min5/hooks/log.sh"
cp verifier/hooks/parallel-{a,b,c}.sh "$tmp/min5/verifier-min5/hooks/"
cp verifier/hooks/block.sh "$tmp/min5/verifier-min5/hooks/block.sh"
# strip UserPromptExpansion like real package-cowork
jq 'del(.hooks.UserPromptExpansion)' "$tmp/min5/verifier-min5/hooks/hooks.json" > "$tmp/min5/verifier-min5/hooks/hooks.json.tmp"
mv "$tmp/min5/verifier-min5/hooks/hooks.json.tmp" "$tmp/min5/verifier-min5/hooks/hooks.json"
cp "$tmp/min4/verifier-min4/skills/hello/SKILL.md" "$tmp/min5/verifier-min5/skills/hello/SKILL.md"
( cd "$tmp/min5" && zip -r "${OUT_ABS}/verifier-min5.zip" verifier-min5 >/dev/null )

# --- min6: min5 + a skill that has a frontmatter PreToolUse:Bash hook (simple, no exotic vars) ---
mkdir -p "$tmp/min6/verifier-min6/.claude-plugin" "$tmp/min6/verifier-min6/hooks" "$tmp/min6/verifier-min6/skills/hello-fm"
cp "$tmp/min5/verifier-min5/.claude-plugin/plugin.json" "$tmp/min6/verifier-min6/.claude-plugin/plugin.json"
sed -i 's/"verifier-min5"/"verifier-min6"/g' "$tmp/min6/verifier-min6/.claude-plugin/plugin.json"
sed -i 's/min4 + full plugin-level hooks/min5 + skill with frontmatter PreToolUse:Bash/' "$tmp/min6/verifier-min6/.claude-plugin/plugin.json"
cp "$tmp/min5/verifier-min5/hooks/hooks.json" "$tmp/min6/verifier-min6/hooks/hooks.json"
cp "$tmp/min5/verifier-min5/hooks/log.sh" "$tmp/min6/verifier-min6/hooks/log.sh"
cp "$tmp/min5/verifier-min5/hooks/parallel-"{a,b,c}.sh "$tmp/min6/verifier-min6/hooks/"
cp "$tmp/min5/verifier-min5/hooks/block.sh" "$tmp/min6/verifier-min6/hooks/block.sh"
cat > "$tmp/min6/verifier-min6/skills/hello-fm/SKILL.md" <<'MD'
---
name: hello-fm
description: A user-invocable skill with a frontmatter PreToolUse:Bash hook.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'echo "[hello-fm] PreToolUse:Bash hook fired"'
---

# hello-fm

Skill with a frontmatter PreToolUse:Bash hook. Run `echo hello world from cowork`.
MD
( cd "$tmp/min6" && zip -r "${OUT_ABS}/verifier-min6.zip" verifier-min6 >/dev/null )

# Bisect the real verifier's 22 skills: first half vs second half
# First half:  00, 01, 02, 03, 04, 05, 06, 07, 08, 08b, 09  (11 skills)
# Second half: 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21  (12 skills)
FIRST_HALF=(00-canary 01-env-propagation 02-substitution-allowlist 03-shell-binsh 04-sensitive-leak 05-userconfig-trigger 06-marketplace-cache 07-skill-body-subst 08-frontmatter-timing 08b-self-block-attempt 09-slash-vs-natural)
SECOND_HALF=(10-parallel-hook-firing 11-block-target 12-block-self 13-cowork-pretooluse 14-cowork-parser 15-cowork-file-io 16-cowork-path-forms 17-cowork-bash-mount 18-cowork-data-isolation 19-cowork-resume 20-cowork-validation 21-cowork-connected-folder)

build_bisect() {
  local label="$1"; shift
  local skill_dirs=("$@")
  local dest="$tmp/$label/verifier-$label"
  mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills"
  cp "$tmp/min5/verifier-min5/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
  sed -i "s/\"verifier-min5\"/\"verifier-$label\"/g" "$dest/.claude-plugin/plugin.json"
  sed -i "s/min4 + full plugin-level hooks/bisect $label: $(echo ${skill_dirs[*]} | tr ' ' ',')/" "$dest/.claude-plugin/plugin.json"
  cp "$tmp/min5/verifier-min5/hooks/"*.sh "$tmp/min5/verifier-min5/hooks/hooks.json" "$dest/hooks/"
  for s in "${skill_dirs[@]}"; do
    cp -r "verifier/skills/$s" "$dest/skills/$s"
  done
  ( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
}

build_bisect min7-first-half "${FIRST_HALF[@]}"
build_bisect min8-second-half "${SECOND_HALF[@]}"

# --- min9: same as min7-first-half but with all skill frontmatter hooks STRIPPED ---
# Tests whether complex frontmatter hook command syntax is the rejection cause.
dest="$tmp/min9/verifier-min9"
mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills"
cp "$tmp/min5/verifier-min5/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
sed -i 's/"verifier-min5"/"verifier-min9"/g' "$dest/.claude-plugin/plugin.json"
sed -i 's/min4 + full plugin-level hooks/min7 first-half but skill frontmatter hooks STRIPPED/' "$dest/.claude-plugin/plugin.json"
cp "$tmp/min5/verifier-min5/hooks/"*.sh "$tmp/min5/verifier-min5/hooks/hooks.json" "$dest/hooks/"
for s in "${FIRST_HALF[@]}"; do
  cp -r "verifier/skills/$s" "$dest/skills/$s"
  # Strip the YAML frontmatter `hooks:` block (between `hooks:` line and the closing `---`).
  # Use awk to drop lines from `^hooks:` through the YAML frontmatter terminator,
  # preserving everything before `hooks:` and after the closing `---`.
  python3 - "$dest/skills/$s/SKILL.md" <<'PY'
import sys, re
p = sys.argv[1]
text = open(p).read()
# Match the YAML frontmatter (everything between the first two --- lines).
m = re.match(r'^(---\n)(.*?\n)(---\n)(.*)$', text, re.DOTALL)
if not m:
    sys.exit(0)
fm_body = m.group(2)
# Drop the entire `hooks:` block (assume it's followed by indented children until next top-level key or end).
out_lines = []
in_hooks = False
for line in fm_body.split('\n'):
    if line.startswith('hooks:'):
        in_hooks = True
        continue
    if in_hooks:
        if line == '' or line.startswith(' ') or line.startswith('\t'):
            continue
        in_hooks = False
    out_lines.append(line)
new_fm = '\n'.join(out_lines)
open(p, 'w').write(m.group(1) + new_fm + m.group(3) + m.group(4))
PY
done
( cd "$tmp/min9" && zip -r "${OUT_ABS}/verifier-min9-stripped-frontmatter.zip" verifier-min9 >/dev/null )

# --- min10: min6 + just 00-canary skill from real verifier (intact) ---
dest="$tmp/min10/verifier-min10"
mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills"
cp "$tmp/min6/verifier-min6/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
sed -i 's/"verifier-min6"/"verifier-min10"/g' "$dest/.claude-plugin/plugin.json"
sed -i 's/min5 + skill with frontmatter PreToolUse:Bash/min6 + real 00-canary skill (intact)/' "$dest/.claude-plugin/plugin.json"
cp "$tmp/min6/verifier-min6/hooks/"*.sh "$tmp/min6/verifier-min6/hooks/hooks.json" "$dest/hooks/"
cp "$tmp/min6/verifier-min6/skills/hello-fm/SKILL.md" "$dest/skills/" || true
mkdir -p "$dest/skills/hello-fm"
mv "$dest/skills/SKILL.md" "$dest/skills/hello-fm/SKILL.md" 2>/dev/null
cp -r verifier/skills/00-canary "$dest/skills/00-canary"
( cd "$tmp/min10" && zip -r "${OUT_ABS}/verifier-min10-add-canary.zip" verifier-min10 >/dev/null )

# --- min11: min6 + 00-canary with body stripped of ${...} substitution markers ---
dest="$tmp/min11/verifier-min11"
mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/00-canary-no-subst"
cp "$tmp/min10/verifier-min10/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
sed -i 's/"verifier-min10"/"verifier-min11"/g' "$dest/.claude-plugin/plugin.json"
sed -i 's/min6 + real 00-canary skill (intact)/min6 + 00-canary with body ${...} markers stripped/' "$dest/.claude-plugin/plugin.json"
cp "$tmp/min10/verifier-min10/hooks/"*.sh "$tmp/min10/verifier-min10/hooks/hooks.json" "$dest/hooks/"
mkdir -p "$dest/skills/hello-fm"
cp "$tmp/min10/verifier-min10/skills/hello-fm/SKILL.md" "$dest/skills/hello-fm/SKILL.md"
# Build a 00-canary clone with stripped body
cat > "$dest/skills/00-canary-no-subst/SKILL.md" <<'MD'
---
name: 00-canary-no-subst
description: 00-canary clone with frontmatter hooks AND all body ${...} stripped.
user-invocable: true
---

# 00-canary-no-subst

Body intentionally avoids any dollar-curly-brace substitution markers.

## step 1

Run a bash command:

```bash
echo "canary alive"
```
MD
( cd "$tmp/min11" && zip -r "${OUT_ABS}/verifier-min11-canary-no-subst.zip" verifier-min11 >/dev/null )

# --- min12: min6 + first 5 real skills (00..04) ---
dest="$tmp/min12/verifier-min12"
mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/hello-fm"
cp "$tmp/min10/verifier-min10/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
sed -i 's/"verifier-min10"/"verifier-min12"/g' "$dest/.claude-plugin/plugin.json"
sed -i 's/min6 + real 00-canary skill (intact)/min6 + first 5 real skills 00..04/' "$dest/.claude-plugin/plugin.json"
cp "$tmp/min10/verifier-min10/hooks/"*.sh "$tmp/min10/verifier-min10/hooks/hooks.json" "$dest/hooks/"
cp "$tmp/min10/verifier-min10/skills/hello-fm/SKILL.md" "$dest/skills/hello-fm/SKILL.md"
for s in 00-canary 01-env-propagation 02-substitution-allowlist 03-shell-binsh 04-sensitive-leak; do
  cp -r "verifier/skills/$s" "$dest/skills/$s"
done
( cd "$tmp/min12" && zip -r "${OUT_ABS}/verifier-min12-first-5.zip" verifier-min12 >/dev/null )

# --- min13: min6 + 11 copies of a no-subst simple skill ---
dest="$tmp/min13/verifier-min13"
mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/hello-fm"
cp "$tmp/min11/verifier-min11/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
sed -i 's/"verifier-min11"/"verifier-min13"/g' "$dest/.claude-plugin/plugin.json"
sed -i 's/min6 + 00-canary with body \${...} markers stripped/min6 + 11 copies of simple no-subst skill (tests count threshold)/' "$dest/.claude-plugin/plugin.json"
cp "$tmp/min11/verifier-min11/hooks/"*.sh "$tmp/min11/verifier-min11/hooks/hooks.json" "$dest/hooks/"
cp "$tmp/min11/verifier-min11/skills/hello-fm/SKILL.md" "$dest/skills/hello-fm/SKILL.md"
for i in $(seq -w 1 11); do
  mkdir -p "$dest/skills/clone-$i"
  cat > "$dest/skills/clone-$i/SKILL.md" <<MD
---
name: clone-$i
description: Simple no-frontmatter no-subst clone skill (count test instance $i).
user-invocable: true
---

# clone-$i

Plain text body, no \${...} markers. Run \`echo clone-$i alive\`.
MD
done
( cd "$tmp/min13" && zip -r "${OUT_ABS}/verifier-min13-11-clones.zip" verifier-min13 >/dev/null )

# Helper to build a "min12-bisect-X" with min10 baseline + listed real skill dirs
build_min12_bisect() {
  local label="$1"; shift
  local skill_dirs=("$@")
  local dest="$tmp/$label/verifier-$label"
  mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/hello-fm"
  cp "$tmp/min10/verifier-min10/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
  sed -i "s/\"verifier-min10\"/\"verifier-$label\"/g" "$dest/.claude-plugin/plugin.json"
  sed -i "s|min6 + real 00-canary skill (intact)|min12 bisect $label: $(echo ${skill_dirs[*]} | tr ' ' ',')|" "$dest/.claude-plugin/plugin.json"
  cp "$tmp/min10/verifier-min10/hooks/"*.sh "$tmp/min10/verifier-min10/hooks/hooks.json" "$dest/hooks/"
  cp "$tmp/min10/verifier-min10/skills/hello-fm/SKILL.md" "$dest/skills/hello-fm/SKILL.md"
  for s in "${skill_dirs[@]}"; do
    cp -r "verifier/skills/$s" "$dest/skills/$s"
  done
  ( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
}

# min14: 00 + 01 + 02
build_min12_bisect min14-001-002 00-canary 01-env-propagation 02-substitution-allowlist
# min15: 00 + 03 + 04
build_min12_bisect min15-003-004 00-canary 03-shell-binsh 04-sensitive-leak

# min16: 00 + 03 alone
build_min12_bisect min16-003-only 00-canary 03-shell-binsh
# min17: 00 + 04 alone
build_min12_bisect min17-004-only 00-canary 04-sensitive-leak

# --- min18: 00 + 03 with ${PWD^^} stripped from 03's frontmatter ---
dest="$tmp/min18/verifier-min18"
mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/hello-fm" "$dest/skills/00-canary" "$dest/skills/03-shell-binsh"
cp "$tmp/min10/verifier-min10/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
sed -i 's/"verifier-min10"/"verifier-min18"/g' "$dest/.claude-plugin/plugin.json"
sed -i 's|min6 + real 00-canary skill (intact)|00 + 03 with ${PWD^^} stripped|' "$dest/.claude-plugin/plugin.json"
cp "$tmp/min10/verifier-min10/hooks/"*.sh "$tmp/min10/verifier-min10/hooks/hooks.json" "$dest/hooks/"
cp "$tmp/min10/verifier-min10/skills/hello-fm/SKILL.md" "$dest/skills/hello-fm/SKILL.md"
cp -r verifier/skills/00-canary "$dest/skills/"
cp -r verifier/skills/03-shell-binsh "$dest/skills/"
# Replace `${PWD^^}` with `PWD_PLACEHOLDER` in 03's SKILL.md
sed -i 's|\${PWD^^}|PWD_PLACEHOLDER|g' "$dest/skills/03-shell-binsh/SKILL.md"
( cd "$tmp/min18" && zip -r "${OUT_ABS}/verifier-min18-no-pwd-uppercase.zip" verifier-min18 >/dev/null )

# --- min19: 00 + 03 with the ENTIRE frontmatter hooks block stripped from 03 ---
dest="$tmp/min19/verifier-min19"
mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/hello-fm" "$dest/skills/00-canary" "$dest/skills/03-shell-binsh"
cp "$tmp/min10/verifier-min10/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
sed -i 's/"verifier-min10"/"verifier-min19"/g' "$dest/.claude-plugin/plugin.json"
sed -i 's|min6 + real 00-canary skill (intact)|00 + 03 with 03 frontmatter hooks block stripped|' "$dest/.claude-plugin/plugin.json"
cp "$tmp/min10/verifier-min10/hooks/"*.sh "$tmp/min10/verifier-min10/hooks/hooks.json" "$dest/hooks/"
cp "$tmp/min10/verifier-min10/skills/hello-fm/SKILL.md" "$dest/skills/hello-fm/SKILL.md"
cp -r verifier/skills/00-canary "$dest/skills/"
cp -r verifier/skills/03-shell-binsh "$dest/skills/"
python3 - "$dest/skills/03-shell-binsh/SKILL.md" <<'PY'
import sys, re
p = sys.argv[1]
text = open(p).read()
m = re.match(r'^(---\n)(.*?\n)(---\n)(.*)$', text, re.DOTALL)
if not m: sys.exit(0)
fm_body = m.group(2)
out_lines = []
in_hooks = False
for line in fm_body.split('\n'):
    if line.startswith('hooks:'):
        in_hooks = True
        continue
    if in_hooks:
        if line == '' or line.startswith(' ') or line.startswith('\t'):
            continue
        in_hooks = False
    out_lines.append(line)
open(p, 'w').write(m.group(1) + '\n'.join(out_lines) + m.group(3) + m.group(4))
PY
( cd "$tmp/min19" && zip -r "${OUT_ABS}/verifier-min19-strip-03-frontmatter.zip" verifier-min19 >/dev/null )

# --- min20: 00 + 03 with EVERY `${PWD^^}` replaced (both frontmatter and body) ---
dest="$tmp/min20/verifier-min20"
mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/hello-fm" "$dest/skills/00-canary" "$dest/skills/03-shell-binsh"
cp "$tmp/min10/verifier-min10/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
sed -i 's/"verifier-min10"/"verifier-min20"/g' "$dest/.claude-plugin/plugin.json"
sed -i 's|min6 + real 00-canary skill (intact)|00 + 03 ALL \${PWD^^} replaced|' "$dest/.claude-plugin/plugin.json"
cp "$tmp/min10/verifier-min10/hooks/"*.sh "$tmp/min10/verifier-min10/hooks/hooks.json" "$dest/hooks/"
cp "$tmp/min10/verifier-min10/skills/hello-fm/SKILL.md" "$dest/skills/hello-fm/SKILL.md"
cp -r verifier/skills/00-canary "$dest/skills/"
cp -r verifier/skills/03-shell-binsh "$dest/skills/"
# Replace ${PWD^^} EVERYWHERE in 03's SKILL.md (both frontmatter and body code blocks)
sed -i 's|\${PWD^^}|PWD_PLACEHOLDER|g' "$dest/skills/03-shell-binsh/SKILL.md"
( cd "$tmp/min20" && zip -r "${OUT_ABS}/verifier-min20-strip-all-pwd-uppercase.zip" verifier-min20 >/dev/null )

# --- min21: 00 + a stub at name=03-shell-binsh (verifier dir, but body is minimal hello-like) ---
dest="$tmp/min21/verifier-min21"
mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/hello-fm" "$dest/skills/00-canary" "$dest/skills/03-shell-binsh"
cp "$tmp/min10/verifier-min10/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
sed -i 's/"verifier-min10"/"verifier-min21"/g' "$dest/.claude-plugin/plugin.json"
sed -i 's|min6 + real 00-canary skill (intact)|00 + stub at 03-shell-binsh (name kept, body minimal)|' "$dest/.claude-plugin/plugin.json"
cp "$tmp/min10/verifier-min10/hooks/"*.sh "$tmp/min10/verifier-min10/hooks/hooks.json" "$dest/hooks/"
cp "$tmp/min10/verifier-min10/skills/hello-fm/SKILL.md" "$dest/skills/hello-fm/SKILL.md"
cp -r verifier/skills/00-canary "$dest/skills/"
cat > "$dest/skills/03-shell-binsh/SKILL.md" <<'MD'
---
name: 03-shell-binsh
description: Stub for narrowing the Cowork rejection. Minimal body.
user-invocable: true
---

# 03-shell-binsh stub

Run a bash command:

```bash
echo "03 stub alive"
```
MD
( cd "$tmp/min21" && zip -r "${OUT_ABS}/verifier-min21-stub-03.zip" verifier-min21 >/dev/null )

# --- min22: min21 + 03 frontmatter restored (with PWD^^ replaced) ---
dest="$tmp/min22/verifier-min22"
mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/hello-fm" "$dest/skills/00-canary" "$dest/skills/03-shell-binsh"
cp "$tmp/min21/verifier-min21/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
sed -i 's/"verifier-min21"/"verifier-min22"/g' "$dest/.claude-plugin/plugin.json"
sed -i 's|00 + stub at 03-shell-binsh (name kept, body minimal)|min21 + restore 03 frontmatter (PWD^^ replaced)|' "$dest/.claude-plugin/plugin.json"
cp "$tmp/min21/verifier-min21/hooks/"*.sh "$tmp/min21/verifier-min21/hooks/hooks.json" "$dest/hooks/"
cp "$tmp/min21/verifier-min21/skills/hello-fm/SKILL.md" "$dest/skills/hello-fm/SKILL.md"
cp -r verifier/skills/00-canary "$dest/skills/"
# 03 with real frontmatter but stub body
python3 - "$dest/skills/03-shell-binsh/SKILL.md" verifier/skills/03-shell-binsh/SKILL.md <<'PY'
import sys, re
out_path = sys.argv[1]
src_path = sys.argv[2]
src = open(src_path).read()
m = re.match(r'^(---\n)(.*?\n)(---\n)(.*)$', src, re.DOTALL)
frontmatter = m.group(2).replace('${PWD^^}', 'PWD_PLACEHOLDER')
new_doc = m.group(1) + frontmatter + m.group(3) + "\n# 03-shell-binsh stub\n\nMinimal body (frontmatter restored).\n\n```bash\necho \"03 frontmatter restore test\"\n```\n"
open(out_path, 'w').write(new_doc)
PY
( cd "$tmp/min22" && zip -r "${OUT_ABS}/verifier-min22-restore-frontmatter.zip" verifier-min22 >/dev/null )

# --- min23: min21 + 03 body restored fully BUT keep stub frontmatter ---
dest="$tmp/min23/verifier-min23"
mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/hello-fm" "$dest/skills/00-canary" "$dest/skills/03-shell-binsh"
cp "$tmp/min21/verifier-min21/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
sed -i 's/"verifier-min21"/"verifier-min23"/g' "$dest/.claude-plugin/plugin.json"
sed -i 's|00 + stub at 03-shell-binsh (name kept, body minimal)|min21 + restore 03 body (frontmatter still stub)|' "$dest/.claude-plugin/plugin.json"
cp "$tmp/min21/verifier-min21/hooks/"*.sh "$tmp/min21/verifier-min21/hooks/hooks.json" "$dest/hooks/"
cp "$tmp/min21/verifier-min21/skills/hello-fm/SKILL.md" "$dest/skills/hello-fm/SKILL.md"
cp -r verifier/skills/00-canary "$dest/skills/"
# 03 with stub frontmatter but real body
python3 - "$dest/skills/03-shell-binsh/SKILL.md" verifier/skills/03-shell-binsh/SKILL.md <<'PY'
import sys, re
out_path = sys.argv[1]
src_path = sys.argv[2]
src = open(src_path).read()
m = re.match(r'^(---\n)(.*?\n)(---\n)(.*)$', src, re.DOTALL)
body = m.group(4)
stub_fm = "name: 03-shell-binsh\ndescription: Stub frontmatter, real body restored.\nuser-invocable: true\n"
new_doc = m.group(1) + stub_fm + m.group(3) + body
open(out_path, 'w').write(new_doc)
PY
( cd "$tmp/min23" && zip -r "${OUT_ABS}/verifier-min23-restore-body.zip" verifier-min23 >/dev/null )

# Helper: build "00 + 03 stub body + custom frontmatter command"
build_03_fm() {
  local label="$1"
  local fm_command="$2"
  local dest="$tmp/$label/verifier-$label"
  mkdir -p "$dest/.claude-plugin" "$dest/hooks" "$dest/skills/hello-fm" "$dest/skills/00-canary" "$dest/skills/03-shell-binsh"
  cp "$tmp/min21/verifier-min21/.claude-plugin/plugin.json" "$dest/.claude-plugin/plugin.json"
  sed -i "s/\"verifier-min21\"/\"verifier-$label\"/g" "$dest/.claude-plugin/plugin.json"
  cp "$tmp/min21/verifier-min21/hooks/"*.sh "$tmp/min21/verifier-min21/hooks/hooks.json" "$dest/hooks/"
  cp "$tmp/min21/verifier-min21/skills/hello-fm/SKILL.md" "$dest/skills/hello-fm/SKILL.md"
  cp -r verifier/skills/00-canary "$dest/skills/"
  cat > "$dest/skills/03-shell-binsh/SKILL.md" <<MD
---
name: 03-shell-binsh
description: Stub for narrowing — frontmatter command varies, body is minimal.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: '$fm_command'
---

# 03 stub with custom frontmatter command ($label)

\`\`\`bash
echo "stub body"
\`\`\`
MD
  ( cd "$tmp/$label" && zip -r "${OUT_ABS}/verifier-$label.zip" "verifier-$label" >/dev/null )
}

# min24: super-simple frontmatter command (just printf, no braces/redirects)
build_03_fm min24-fm-simple-printf 'printf "[03-FM %s]\n" "$(date -Iseconds)"'
# min25: + brace group {}
build_03_fm min25-fm-brace 'sh -c "printf [03-FM-brace]"'
# min26: + redirect >>
build_03_fm min26-fm-redirect 'echo redirect-test >> /tmp/03-redir.log'
# min27: + 2>&1 stderr-to-stdout
build_03_fm min27-fm-stderr 'echo stderr-test 2>&1'
# min28: + ; exit 0 idiom
build_03_fm min28-fm-exit 'echo exit-test ; exit 0'

# Test specific variable references — Cowork validator may reject unknown var prefixes
build_03_fm min29-fm-bash-ver 'echo "BASH_VERSION=[$BASH_VERSION]"'
build_03_fm min30-fm-bash-ver-literal 'echo "BASH_VERSION=[unknown]"'
build_03_fm min31-fm-verifier-version 'echo "VER=${VERIFIER_VERSION_DIR:-v-unknown}"'
build_03_fm min32-fm-claude-only 'echo "ROOT=${CLAUDE_PLUGIN_ROOT}"'

ls -la "$out_dir"/verifier-min*.zip
cp "$out_dir"/verifier-min*.zip /mnt/c/Users/knaga/OneDrive/Desktop/ 2>/dev/null && \
  ls /mnt/c/Users/knaga/OneDrive/Desktop/verifier-min*.zip
