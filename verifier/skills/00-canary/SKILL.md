---
name: 00-canary
description: Observation infrastructure canary. Verifies that plugin-level hooks fire (via session-start log), that skill frontmatter hooks register and fire after first invoke, and that bash tool subprocess can write to the findings directory. Run this BEFORE any other probe — if this FAILs, the verdict of every later probe is CANARY-FAILED.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'mkdir -p "$CLAUDE_PROJECT_DIR/findings/${VERIFIER_VERSION_DIR:-v-unknown}/${CLAUDE_SESSION_ID:-no-sid}" && printf "[00-canary-fm %s] tag=fm-registered ROOT=[%s] DATA=[%s] SESSION=[%s]\n" "$(date -Iseconds)" "$CLAUDE_PLUGIN_ROOT" "$CLAUDE_PLUGIN_DATA" "$CLAUDE_SESSION_ID" >> "$CLAUDE_PROJECT_DIR/findings/${VERIFIER_VERSION_DIR:-v-unknown}/${CLAUDE_SESSION_ID:-no-sid}/probe.log"'
---

# 00-canary

このスキルは**観測基盤の生存確認**です。後続のすべての probe の前提となるため、最初に走らせてください。

次の bash を1つずつ実行してください：

## step 1: alive-check tag を skill body から出力

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
printf '[00-canary-body %s] tag=alive-check sid=%s\n' "$(date -Iseconds)" "$sid" | tee -a "$out_dir/probe.log"
```

## step 2: log file の存在と中身を確認

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
echo "=== hooks.log ($proj/findings/$ver/$sid/hooks.log) ==="
ls -la "$proj/findings/$ver/$sid/" 2>&1
echo
echo "=== probe.log ==="
cat "$proj/findings/$ver/$sid/probe.log" 2>&1
echo
echo "=== hooks.log (last 60 lines) ==="
tail -n 60 "$proj/findings/$ver/$sid/hooks.log" 2>&1
```

完了したら exit してください。`./scripts/assert.sh 00` で観測基盤の生存判定が走ります。
