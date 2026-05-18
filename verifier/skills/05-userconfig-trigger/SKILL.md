---
name: 05-userconfig-trigger
description: Probe userConfig prompt trigger rules (§1.5). Manual verification of 4 routes — install/enable silent, /plugins UI prompt, disable→enable conditional, hook error when referenced-but-unset.
user-invocable: true
---

# 05-userconfig-trigger

§1.5 — 4 trigger ルートを観察。完全手動 probe。

**手順は MASTER-RUNBOOK の 05 セクションを参照**してください。SKILL では log 確認だけ：

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
{
  printf '[05-BODY %s] tag=alive-check\n' "$(date -Iseconds)"
  printf '[05-BODY] hello=[%s] secret=[%s]\n' "${CLAUDE_PLUGIN_OPTION_HELLO_MESSAGE-(unset)}" "${CLAUDE_PLUGIN_OPTION_API_SECRET-(unset)}"
} | tee -a "$out_dir/probe.log"

echo "=== install.log: search for 'Plugin option ... isn't set' ==="
grep -nE "Plugin option.*isn.t set|Plugin option.*is not set" "$proj/findings/$ver/install.log" 2>&1 || echo "(no hook error in install.log — userConfig may already be set)"

echo
echo "=== settings.json pluginConfigs ==="
cat "$CLAUDE_CONFIG_DIR/settings.json" 2>&1 | head -40
```

完了して exit、`./scripts/assert.sh 05`（半自動）。
