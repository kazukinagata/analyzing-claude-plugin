---
name: Uppercase-Skill-Name
description: "Used by probe 20 to trigger validation rejection on Cowork via non-kebab-case naming. NOTE this skill folder is named lowercase but the frontmatter name field intentionally violates the rule."
user-invocable: false
---

# Uppercase-Skill-Name

frontmatter `name` がキャメル/パスカルケースなので、Cowork の名前 validator が拒否する想定。CLI は具体的なエラー（`Plugin name must be kebab-case`）を返すはず。
