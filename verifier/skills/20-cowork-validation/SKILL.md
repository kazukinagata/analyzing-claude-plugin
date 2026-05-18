---
name: 20-cowork-validation
description: "CLI validates plugins fully; Cowork reports a generic Plugin validation failed without exposing the cause (research section 2.3). Runs claude plugin validate on isolated violator variants."
user-invocable: true
---

# 20-cowork-validation

§2.3 — Cowork での **validation 失敗の理由が出ない**。CLI は具体的なエラー。

## step 1: alive-check と CLI validation baseline

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
printf '[20-BODY %s] tag=alive-check\n' "$(date -Iseconds)" | tee -a "$out_dir/probe.log"
echo
echo "=== 20a: UserPromptExpansion variant plugin ===" | tee -a "$out_dir/probe.log"
claude plugin validate "$proj/verifier-violator-userpromptexpansion" 2>&1 | tee -a "$out_dir/probe.log" || true
echo
echo "=== 20b: uppercase plugin name variant ===" | tee -a "$out_dir/probe.log"
claude plugin validate "$proj/verifier-violator-uppercase-name" 2>&1 | tee -a "$out_dir/probe.log" || true
```

完了して exit、`./scripts/assert.sh 20`。
