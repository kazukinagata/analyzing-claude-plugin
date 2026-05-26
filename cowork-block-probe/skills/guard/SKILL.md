---
name: guard
description: Arms a skill-to-skill block via a frontmatter PreToolUse Skill hook. After invoking this, a natural-language attempt to run the victim skill should be blocked if the block decision is honored.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Skill"
      hooks:
        - type: command
          command: 'bash -c ''input=$(cat); if printf "%s" "$input" | grep -q "victim"; then printf "%s" "{\"decision\":\"block\",\"reason\":\"BLOCKED-BY-GUARD-HOOK\"}"; fi'''
---

# guard

skill-to-skill block を arm する probe です。次の bash を実行してください（これで guard の frontmatter hook が登録されます）。

```bash
echo "GUARD-ARMED-MARKER host=$(hostname)"
```

この後、**victim skill を自然言語で**起動してみてください（slash ではなく、例：「victim スキルを実行して」）。slash 経由だと PreToolUse:Skill が発火しないため、必ず自然言語で。

判定：

- block が効いた場合 → victim は起動せず、`BLOCKED-BY-GUARD-HOOK` という reason が出る
- block が効かない場合 → victim の body が走り `VICTIM-RAN-MARKER` が出る
