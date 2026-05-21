---
name: 11-block-target
description: §2.4. Target skill for the block pair (11+12). After 12-block-self is invoked (registering its frontmatter PreToolUse:Skill hook), invoking 11-block-target should be blocked.
user-invocable: true
---

# 11-block-target

これはペアで動作する probe の **target 側** です。12-block-self の frontmatter hook が PreToolUse:Skill で block するべきスキル。

## step 1: alive-check

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
printf '[11-BODY %s] tag=alive-check (target ran — block did not fire)\n' "$(date -Iseconds)" | tee -a "$out_dir/probe.log"
```

`tag=alive-check` が log に出れば「block されなかった」、出なければ「block 成功」。
