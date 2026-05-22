---
name: 17-cowork-bash-mount
description: "Cowork mounts the plugin install dir under /sessions/CODENAME/mnt/.remote-plugins/ read-only. Bundled scripts can be launched via relative path; CLAUDE_SKILL_DIR expands to a Windows path that fails directly. CLI baseline lets both patterns work. See research section 2.10."
user-invocable: true
---

# 17-cowork-bash-mount

§2.10 — bundled script の起動パターン 2 種 + 罠（`mkdir -p` ゴミ、`tee` silent fail）。

## step 1: alive-check と Pattern A (relative path / find)

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
{
  printf '[17-BODY %s] tag=alive-check\n' "$(date -Iseconds)"
  printf '[17-BODY] CLAUDE_SKILL_DIR=[%s]\n' "${CLAUDE_SKILL_DIR-(unset)}"
  printf '[17-BODY] CLAUDE_PLUGIN_ROOT=[%s]\n' "${CLAUDE_PLUGIN_ROOT-(unset)}"
} | tee -a "$out_dir/probe.log"

# Pattern A: find then cd
skill_dir=$(find /sessions -path '*/skills/17-cowork-bash-mount' -type d 2>/dev/null | head -1)
if [ -z "$skill_dir" ]; then
  # CLI: SKILL_DIR is a Linux path so use it directly
  skill_dir="${CLAUDE_SKILL_DIR}"
fi
echo "Pattern A: cd $skill_dir && bash scripts/say-hi.sh" | tee -a "$out_dir/probe.log"
( cd "$skill_dir" 2>/dev/null && bash scripts/say-hi.sh ) 2>&1 | tee -a "$out_dir/probe.log"
```

## step 2: Pattern B (${CLAUDE_SKILL_DIR} direct, expected to FAIL on Cowork)

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
echo "Pattern B: bash \"${CLAUDE_SKILL_DIR}/scripts/say-hi.sh\"" | tee -a "$out_dir/probe.log"
bash "${CLAUDE_SKILL_DIR}/scripts/say-hi.sh" 2>&1 | tee -a "$out_dir/probe.log" || echo "[17-PATTERN-B exited non-zero (expected on Cowork)]" | tee -a "$out_dir/probe.log"
```

## step 3: 罠の確認 (mkdir -p $DATA gomi + ${CLAUDE_PROJECT_DIR:-$PWD} fallback)

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
before_pwd_listing=$(ls "$PWD" 2>/dev/null | head -20)
mkdir -p "${CLAUDE_PLUGIN_DATA}" 2>&1
after_pwd_listing=$(ls "$PWD" 2>/dev/null | head -20)
{
  printf '[17-BODY trap-mkdir] before=%s\n' "$(echo $before_pwd_listing | tr '\n' ' ' | head -c 200)"
  printf '[17-BODY trap-mkdir] after=%s\n' "$(echo $after_pwd_listing | tr '\n' ' ' | head -c 200)"
} | tee -a "$out_dir/probe.log"
```

完了して exit、`./scripts/assert.sh 17`。
