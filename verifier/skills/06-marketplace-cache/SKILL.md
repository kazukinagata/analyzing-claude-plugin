---
name: 06-marketplace-cache
description: Compare CLAUDE_PLUGIN_ROOT with the marketplace cache path (§1.6). Docs say plugins run from cache; observation showed they run from source. This probe lets you classify the current behavior as PASS (finding holds) or DOC-ALIGNED (cache is now used).
user-invocable: true
---

# 06-marketplace-cache

§1.6 — `claude plugin install` した plugin が cache から実行されるか、source から実行されるかを判定。

**事前準備**：`./scripts/install-marketplace.sh` で正式 install 経路を通していること（`--plugin-dir` の ephemeral では §1.6 の判定不可）。

## step 1: invoke 時の CLAUDE_PLUGIN_ROOT と cache dir を比較

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
{
  printf '[06-BODY %s] tag=alive-check\n' "$(date -Iseconds)"
  printf '[06-BODY] CLAUDE_PLUGIN_ROOT=[%s]\n' "${CLAUDE_PLUGIN_ROOT-(unset)}"
  printf '[06-BODY] -- candidate cache dirs --\n'
  find "$CLAUDE_CONFIG_DIR/plugins/cache" -name plugin.json -maxdepth 5 2>/dev/null | sort | head -10
  printf '[06-BODY] -- candidate marketplaces --\n'
  find "$CLAUDE_CONFIG_DIR/plugins/marketplaces" -name marketplace.json -maxdepth 5 2>/dev/null | head -5
  # Compare
  installed_plugin_json=$(find "$CLAUDE_CONFIG_DIR/plugins/cache" -path '*verifier*/plugin.json' -maxdepth 5 2>/dev/null | head -1)
  if [ -n "$installed_plugin_json" ]; then
    cache_dir=$(dirname "$installed_plugin_json")
    printf '[06-BODY] cache_dir=[%s]\n' "$cache_dir"
    if [ "$CLAUDE_PLUGIN_ROOT" = "$cache_dir" ]; then
      printf '[06-BODY] VERDICT=DOC-ALIGNED (root == cache, cache is used at runtime)\n'
    else
      printf '[06-BODY] VERDICT=PASS (root != cache, finding holds: source path used at runtime)\n'
    fi
  else
    printf '[06-BODY] VERDICT=UNKNOWN (no cache plugin.json found)\n'
  fi
} | tee -a "$out_dir/probe.log"
```

完了して exit、`./scripts/assert.sh 06`。
