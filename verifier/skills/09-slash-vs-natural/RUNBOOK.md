# RUNBOOK: 09-slash-vs-natural

## 検証内容（§1.9 / §6.2）

| イベント | slash 経由 | 自然文経由 |
|---|---|---|
| `Skill` tool 呼び出し | ❌ | ✅ |
| `PreToolUse:Skill` | ❌ | ✅ |
| `UserPromptSubmit` | ✅ | ✅ |
| `UserPromptExpansion` (CLI のみ) | ✅ | ❌ |

## 2 セッション運用

### セッション A：slash 経由

```sh
cd /path/to/analyzing-claude-plugin
. scripts/_env.sh
claude --plugin-dir ./verifier
```

プロンプトで：
```
/verifier:09-slash-vs-natural
```

完了して exit。`CLAUDE_SESSION_ID` が異なる sid dir に hooks.log が書かれる。

### セッション B：自然文経由

新規 claude セッション：
```
09-slash-vs-natural という skill を起動してください
```

完了して exit。

### 判定

```sh
ls findings/v2.1.143/                # sid dir が 2 つあるはず
./scripts/assert.sh 09
```

`assert.sh` は両 sid の hooks.log を結合して tag 出現を確認。**slash sid に `tag=pretool-skill` がなく自然文 sid にはある**ことが期待。
