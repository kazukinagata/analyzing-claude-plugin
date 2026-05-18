---
name: 02b-data-in-frontmatter
description: Intentionally violates §1.2 validator rule by referencing ${CLAUDE_PLUGIN_DATA} in skill frontmatter hook. Expected to be blocked at install time with a "plugin-only" error.
user-invocable: false
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'echo "[02b violating] DATA=${CLAUDE_PLUGIN_DATA}"'
---

# 02b-data-in-frontmatter (intentionally invalid)

このスキルはわざと invalid な hook を持っており、Claude Code の validator が install 時に block することを確認するためのものです。手動 invoke しないでください。
