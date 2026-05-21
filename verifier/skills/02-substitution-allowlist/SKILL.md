---
name: 02-substitution-allowlist
description: Probe ${VAR} substitution allowlist in skill body (§1.2). Tests CLAUDE_PLUGIN_ROOT/DATA/SKILL_DIR/SESSION_ID/PROJECT_DIR substitution at invoke time.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'sid="${CLAUDE_SESSION_ID:-no-sid}"; ver="${VERIFIER_VERSION_DIR:-v-unknown}"; out_dir="$CLAUDE_PROJECT_DIR/findings/$ver/$sid"; mkdir -p "$out_dir"; printf "[02-FM %s] tag=fm-registered\n" "$(date -Iseconds)" >> "$out_dir/probe.log"'
---

# 02-substitution-allowlist

§1.2 で予測される置換結果（skill body）：

| 記法 | 期待 |
|---|---|
| `${CLAUDE_PLUGIN_ROOT}` | 絶対 path |
| `${CLAUDE_PLUGIN_DATA}` | 絶対 path |
| `${CLAUDE_SKILL_DIR}` | SKILL.md の dirname の絶対 path |
| `${CLAUDE_SESSION_ID}` | UUID |
| `${CLAUDE_PROJECT_DIR}` | literal のまま残る |

## step 1: 5 種類の `${VAR}` を skill body で echo

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
{
  printf '[02-BODY %s] tag=alive-check\n' "$(date -Iseconds)"
  printf '[02-BODY] SUBST_ROOT=[${CLAUDE_PLUGIN_ROOT}]\n'
  printf '[02-BODY] SUBST_DATA=[${CLAUDE_PLUGIN_DATA}]\n'
  printf '[02-BODY] SUBST_SKILL_DIR=[${CLAUDE_SKILL_DIR}]\n'
  printf '[02-BODY] SUBST_SESSION_ID=[${CLAUDE_SESSION_ID}]\n'
  printf '[02-BODY] SUBST_PROJECT_DIR=[${CLAUDE_PROJECT_DIR}]\n'
} | tee -a "$out_dir/probe.log"
```

## step 2: verifier-violator の validator block 確認

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
echo "=== install.log (search for validator block) ==="
grep -E "plugin-only|CLAUDE_PLUGIN_DATA|skill hooks|Bad substitution" "$proj/findings/$ver/install.log" 2>&1 || echo "no install.log yet (run install-marketplace.sh first)"
echo
echo "=== probe.log tail ==="
sid="${CLAUDE_SESSION_ID:-no-sid}"
tail -n 30 "$proj/findings/$ver/$sid/probe.log"
```

完了したら exit。`./scripts/assert.sh 02`。
