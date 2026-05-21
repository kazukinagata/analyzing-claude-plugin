---
name: 04-sensitive-leak
description: Confirm that userConfig.api_secret (sensitive=true) is exposed as plain text via CLAUDE_PLUGIN_OPTION_API_SECRET in plugin-level hook env (§1.4). "sensitive" affects storage only, not runtime exposure.
user-invocable: true
---

# 04-sensitive-leak

§1.4 — `sensitive: true` は保存先（keychain）の分離のみで、ランタイムでは平文で env に渡る。

**事前準備**：`findings/claude-home/settings.json` または `~/.claude/.credentials.json` に以下を設定済みであること：
- `hello_message = hello-from-cli-CANARY`
- `api_secret = secret-xyz-CANARY`

## step 1: alive-check と hooks.log の env を確認

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
{
  printf '[04-BODY %s] tag=alive-check\n' "$(date -Iseconds)"
  printf '[04-BODY] CLAUDE_PLUGIN_OPTION_HELLO_MESSAGE=[%s]\n' "${CLAUDE_PLUGIN_OPTION_HELLO_MESSAGE-(unset)}"
  printf '[04-BODY] CLAUDE_PLUGIN_OPTION_API_SECRET=[%s]\n' "${CLAUDE_PLUGIN_OPTION_API_SECRET-(unset)}"
} | tee -a "$out_dir/probe.log"
echo
echo "=== hooks.log (plugin-level env) ==="
grep -E "OPTION_HELLO|OPTION_API_SECRET|substituted" "$out_dir/hooks.log" 2>&1 || echo "(no match)"
echo
echo "=== settings.json (pluginConfigs) ==="
cat "$CLAUDE_CONFIG_DIR/settings.json" 2>&1 || echo "(no settings.json)"
echo
echo "=== .credentials.json (if present, contents redacted) ==="
[ -f "$CLAUDE_CONFIG_DIR/.credentials.json" ] && echo "exists at $CLAUDE_CONFIG_DIR/.credentials.json" || echo "(none)"
```

完了して exit、`./scripts/assert.sh 04`。
