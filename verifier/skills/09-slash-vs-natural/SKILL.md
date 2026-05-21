---
name: 09-slash-vs-natural
description: §1.9. Slash invocation does NOT trigger PreToolUse:Skill; natural-language invocation does. UserPromptExpansion fires for slash only.
user-invocable: true
---

# 09-slash-vs-natural

§1.9 — slash 経由は Skill tool を通らない、自然文経由は通る。

## step 1: alive-check

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
printf '[09-BODY %s] tag=alive-check sid=%s\n' "$(date -Iseconds)" "$sid" | tee -a "$out_dir/probe.log"
echo
echo "=== hooks.log tags in this session ==="
grep -E "^=== \[" "$out_dir/hooks.log" 2>&1 | head -20
echo
echo "=== Tag presence ==="
for t in user-prompt-submit user-prompt-expansion pretool-skill pretool-bash session-start; do
  c=$(grep -c "tag=$t" "$out_dir/hooks.log" 2>/dev/null || echo 0)
  printf '  tag=%-25s count=%s\n' "$t" "$c"
done
```

完了して exit。**もう一度別 claude セッションで自然文「`09-slash-vs-natural skill を起動して`」を実行**し、別の sid 配下に同じ skill の log を残す。2 セッション分の sid ディレクトリを比較するのが §1.9 の判定。

`./scripts/assert.sh 09` で判定。
