---
name: 10-parallel-hook-firing
description: §1.10. Verify that hooks within the same array fire in parallel. parallel-a (200ms sleep), parallel-b (400ms sleep), parallel-c (0ms) on SessionStart should produce overlapping start_ns timestamps; finish order should be c < a < b (parallel) not a < b < c (serial).
user-invocable: true
---

# 10-parallel-hook-firing

§1.10 — SessionStart array の 3 hook (parallel-{a,b,c}.sh) が並列実行される。

## step 1: alive-check と parallel timing 分析

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
printf '[10-BODY %s] tag=alive-check\n' "$(date -Iseconds)" | tee -a "$out_dir/probe.log"
echo
echo "=== parallel-{a,b,c} start/end timestamps ==="
grep -E "parallel-[abc]-(start|end)" "$out_dir/hooks.log"
echo
echo "=== finish order analysis ==="
grep -E "parallel-[abc]-end" "$out_dir/hooks.log" | awk -F'ts=' '{
  split($2, a, " "); printf "%s ns\n", a[1]
}' | sort -n
```

完了して exit、`./scripts/assert.sh 10`。並列実行なら end 行の順序は c, a, b（sleep の通り）。
