---
name: block-methods
description: Attempts four bash commands each tagged for a different PreToolUse block method, to see which block methods are honored on CLI vs Cowork.
user-invocable: true
---

# block-methods

plugin-level PreToolUse hook が、bash コマンドの中のマーカーを見て 3 種類のブロック方法を出し分けます。次の 4 つの bash を**順に、それぞれ別々に**実行してください。ブロックされたら、そのブロック理由（`BLK-...`）を報告してください。ブロックされず実行できたら、その出力（`RESULT ... ran`）を報告してください。

1. decision:block 形式のテスト

```bash
echo "RESULT M_DECISION ran host=$(hostname)"
```

2. hookSpecificOutput.permissionDecision:deny 形式のテスト

```bash
echo "RESULT M_PERMISSION ran host=$(hostname)"
```

3. exit 2 形式のテスト

```bash
echo "RESULT M_EXIT2 ran host=$(hostname)"
```

4. コントロール（マーカー無し、常に通るはず）

```bash
echo "RESULT CONTROL ran host=$(hostname)"
```

## 報告フォーマット

各コマンドについて、次のどちらかを明記してください：

- **ブロックされた**：ブロック理由（`BLK-decision` / `BLK-permission` / exit 2 の場合は permission denied 等）
- **実行された**：`RESULT ... ran host=...` の出力

判定：CLI では 3 方式すべてブロックされるはず（CONTROL のみ実行）。Cowork でどれがブロックされ、どれが素通りするかを見ます。
