---
name: uc-check
description: Dumps the four userConfig combinations (sensitive/non-sensitive x required/optional) from skill body and reports plugin-level hook output, to test userConfig UI presence and runtime resolution on CLI vs Cowork.
user-invocable: true
---

# uc-check

userConfig の 4 組み合わせ（機密×必須）を skill body から dump します。次の bash を実行してください。

```bash
echo 'BODY opt_plain=${user_config.opt_plain}'
echo 'BODY req_plain=${user_config.req_plain}'
echo 'BODY opt_secret=${user_config.opt_secret}'
echo 'BODY req_secret=${user_config.req_secret}'
```

実行後、context にある `UC-HOOK ...` の行（plugin-level SessionStart hook 由来）も併せて貼ってください。

## 観測ポイント

- **インストール時**：Cowork で必須（required）の userConfig がある plugin を install したとき、入力 UI / プロンプトが出るか
- **body tier の解決**（skill body）：
  - 非機密（opt_plain / req_plain）：値が set なら実値、unset なら literal `${user_config.KEY}`
  - 機密（opt_secret / req_secret）：`[sensitive option 'KEY' not available in skill content]` の block 文字列（set/unset に関係なく）
- **hook tier の解決**（UC-HOOK 行）：
  - 値が set の entry は実値、unset の entry は silently skip される（行が出ない）
