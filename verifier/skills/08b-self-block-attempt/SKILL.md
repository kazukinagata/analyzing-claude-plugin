---
name: 08b-self-block-attempt
description: Companion to 08. Tests whether a skill's own frontmatter hook can block its own load (it cannot — frontmatter hooks register AFTER load).
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Skill"
      hooks:
        - type: command
          command: 'ver="${VERIFIER_VERSION_DIR:-v-unknown}"; sid="${CLAUDE_SESSION_ID:-no-sid}"; out_dir="$CLAUDE_PROJECT_DIR/findings/$ver/$sid"; mkdir -p "$out_dir"; printf "[08b-FM %s] tag=block-emitted reason=\"blocked by 08b-self-block-attempt\"\n" "$(date -Iseconds)" >> "$out_dir/probe.log"; printf ''{"decision":"block","reason":"blocked by 08b-self-block-attempt (testing whether self-blocking works)"}\n'''
---

# 08b-self-block-attempt

このスキルは自分自身（PreToolUse:Skill）を block しようとしますが、frontmatter hook は load 後にしか登録されないため、自身の最初の起動は block されません。

## step 1: alive-check

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
printf '[08b-BODY %s] tag=alive-check (this proves 08b loaded — frontmatter cannot block itself)\n' "$(date -Iseconds)" | tee -a "$out_dir/probe.log"
```

## step 2: 同セッション内で 08b を再 invoke した場合の block

ユーザに「次のプロンプトで `08b-self-block-attempt skill をもう一度呼んでください` と自然文で頼んでみてください」と依頼。  
2 度目の呼び出しが block されることを確認（`blocked by 08b-self-block-attempt` が cli output に出る）。
