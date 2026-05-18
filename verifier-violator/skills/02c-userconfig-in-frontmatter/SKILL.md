---
name: 02c-userconfig-in-frontmatter
description: "References user_config.KEY in skill frontmatter hook. Validator may pass; /bin/sh should error with Bad substitution at hook execution time."
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'echo "[02c violating] hello=${user_config.hello_message}"'
---

# 02c-userconfig-in-frontmatter (intentionally invalid)

このスキルは frontmatter hook で `${user_config.KEY}` を使い、`/bin/sh` レベルで `Bad substitution` エラーを発生させます。
