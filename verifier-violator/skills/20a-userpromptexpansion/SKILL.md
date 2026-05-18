---
name: 20a-userpromptexpansion
description: "Used by probe 20 to trigger validation rejection on Cowork by including UserPromptExpansion in hooks."
user-invocable: false
hooks:
  UserPromptExpansion:
    - hooks:
        - type: command
          command: 'echo "[20a violating UserPromptExpansion]"'
---

# 20a-userpromptexpansion

このスキルは UserPromptExpansion event を hooks に含めており、Cowork ではプラグイン全体の validation 拒否を狙います。CLI ではおそらく通る（baseline）。
