---
name: victim
description: Target skill for the skill-to-skill block test. If its body runs, the guard's block decision was NOT honored.
user-invocable: true
---

# victim

次の bash を実行してください。

```bash
echo "VICTIM-RAN-MARKER (guard block did NOT work) host=$(hostname)"
```

この行が出たということは、guard の frontmatter PreToolUse:Skill block が効かなかったことを意味します。
