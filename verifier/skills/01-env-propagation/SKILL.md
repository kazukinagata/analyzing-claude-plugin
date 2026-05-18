---
name: 01-env-propagation
description: Probe env propagation across 3 process tiers (§1.1). Compares which CLAUDE_* env vars are set in plugin-level hook vs skill frontmatter hook vs Bash tool subprocess.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'sid="${CLAUDE_SESSION_ID:-no-sid}"; ver="v$(claude --version 2>/dev/null | awk "{print \$1}" || echo unknown)"; out_dir="$CLAUDE_PROJECT_DIR/findings/$ver/$sid"; mkdir -p "$out_dir"; printf "[01-FM %s] tag=fm-registered ROOT=[%s] DATA=[%s] PROJECT_DIR=[%s] OPT_HELLO=[%s] OPT_SECRET=[%s] SESSION_ID=[%s]\n" "$(date -Iseconds)" "${CLAUDE_PLUGIN_ROOT:-(empty)}" "${CLAUDE_PLUGIN_DATA:-(empty)}" "${CLAUDE_PROJECT_DIR:-(empty)}" "${CLAUDE_PLUGIN_OPTION_HELLO_MESSAGE:-(empty)}" "${CLAUDE_PLUGIN_OPTION_API_SECRET:-(empty)}" "${CLAUDE_SESSION_ID:-(empty)}" >> "$out_dir/probe.log"'
---

# 01-env-propagation

§1.1 の env 伝播 3 階層を観測します。

次の bash を順に実行：

## step 1: alive-check と Bash tool 側 env を1ショットで dump

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
{
  printf '[01-BODY %s] tag=alive-check\n' "$(date -Iseconds)"
  printf '[01-BODY] CLAUDE_PLUGIN_ROOT=[%s]\n' "${CLAUDE_PLUGIN_ROOT-(unset)}"
  printf '[01-BODY] CLAUDE_PLUGIN_DATA=[%s]\n' "${CLAUDE_PLUGIN_DATA-(unset)}"
  printf '[01-BODY] CLAUDE_PROJECT_DIR=[%s]\n' "${CLAUDE_PROJECT_DIR-(unset)}"
  printf '[01-BODY] CLAUDE_CODE_REMOTE=[%s]\n' "${CLAUDE_CODE_REMOTE-(unset)}"
  printf '[01-BODY] CLAUDE_PLUGIN_OPTION_HELLO_MESSAGE=[%s]\n' "${CLAUDE_PLUGIN_OPTION_HELLO_MESSAGE-(unset)}"
  printf '[01-BODY] CLAUDE_PLUGIN_OPTION_API_SECRET=[%s]\n' "${CLAUDE_PLUGIN_OPTION_API_SECRET-(unset)}"
  printf '[01-BODY] CLAUDE_SKILL_DIR=[%s]\n' "${CLAUDE_SKILL_DIR-(unset)}"
  printf '[01-BODY] CLAUDE_SESSION_ID=[%s]\n' "${CLAUDE_SESSION_ID-(unset)}"
  printf '[01-BODY] CLAUDE_CODE_ENTRYPOINT=[%s]\n' "${CLAUDE_CODE_ENTRYPOINT-(unset)}"
  printf '[01-BODY] CLAUDE_CODE_EXECPATH=[%s]\n' "${CLAUDE_CODE_EXECPATH-(unset)}"
  printf '[01-BODY] ----- all CLAUDE_* -----\n'
  env | grep '^CLAUDE_' | sort
} | tee -a "$out_dir/probe.log"
```

## step 2: hooks.log を見て plugin-level hook 側の env と比較

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
echo "=== hooks.log tail (plugin-level env snapshot) ==="
tail -n 80 "$proj/findings/$ver/$sid/hooks.log"
echo
echo "=== probe.log tail (frontmatter + body env) ==="
tail -n 40 "$proj/findings/$ver/$sid/probe.log"
```

完了したら exit。`./scripts/assert.sh 01` で 3 層の subclaim を判定します。
