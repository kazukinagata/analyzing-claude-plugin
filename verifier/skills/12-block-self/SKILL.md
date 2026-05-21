---
name: 12-block-self
description: §2.4 / §2.5. Self-blocker skill. Its frontmatter PreToolUse:Skill hook returns a JSON block decision for any Skill tool call to 11-block-target. Must be invoked BEFORE 11-block-target so the hook is registered.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Skill"
      hooks:
        - type: command
          command: |
            payload=$(cat 2>/dev/null || true)
            case "$payload" in
              *11-block-target*)
                cat <<JSON
            {"decision":"block","reason":"blocked by 12-block-self frontmatter hook (target was 11-block-target)"}
            JSON
                ;;
              *)
                # Allow other Skill calls
                :
                ;;
            esac
---

# 12-block-self

§2.4 — frontmatter `PreToolUse:Skill` で **11-block-target だけ**を block する。

## step 1: alive-check

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
printf '[12-BODY %s] tag=alive-check (self-blocker registered)\n' "$(date -Iseconds)" | tee -a "$out_dir/probe.log"
```

次のプロンプトで、**自然文で**「`11-block-target` skill を起動してください」とユーザに依頼してもらう（slash 経由は §1.9 によると Skill tool が呼ばれないので block 経路にならない）。
