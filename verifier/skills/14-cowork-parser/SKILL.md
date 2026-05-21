---
name: 14-cowork-parser
description: "Cowork hook command parser is restricted to an echo+bash whitelist; CLI uses /bin/sh. This probe reads the parser-tests.log emitted by a parser-test hook variant."
user-invocable: true
---

# 14-cowork-parser

§2.6 — Cowork hook command parser の whitelist 検証。

**事前準備**：default の hooks.json では parser-test エントリは含まれていないので、検証時には `verifier/hooks/hooks.json` を `verifier/hooks/hooks-parser-tests.json` の内容に**一時的に差し替えて**起動してください（cp で上書きし、検証後に git restore）。詳細は `docs/cowork-runbook.md` 参照。

## step 1: alive-check と parser-tests.log の確認

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
printf '[14-BODY %s] tag=alive-check\n' "$(date -Iseconds)" | tee -a "$out_dir/probe.log"
echo
if [ -f "$proj/findings/parser-tests.log" ]; then
  # Append the raw parser-tests output verbatim. Only the markers that the hook
  # actually emitted will appear here; missing markers stay missing (no false pass).
  echo "=== parser-tests.log (verbatim) ===" | tee -a "$out_dir/probe.log"
  cat "$proj/findings/parser-tests.log" | tee -a "$out_dir/probe.log"
else
  echo "(no parser-tests.log — did you swap hooks.json to hooks-parser-tests.json?)" | tee -a "$out_dir/probe.log"
fi
```

完了して exit、`./scripts/assert.sh 14`。
