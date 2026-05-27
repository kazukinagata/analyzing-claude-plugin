---
name: surface-check
description: Surfaces which of the five SessionStart hook variants (V1-V5) made it into context, to isolate the hook command form that silently fails to surface on Cowork.
user-invocable: true
---

# surface-check

5 種類の SessionStart hook variant が走りました。どれが context に surface したかを確認します。次の bash を実行してください（host 確認用）。

```bash
echo "BODY host=$(hostname)"
```

実行後、context にある以下の marker 行を**すべて**そのまま貼ってください（無いものは「無し」と明記）：

- `[V1] plain` — 単一 echo（対照）
- `[V2] a` / `[V2] b` — 複数文 echo
- `[V3] x` / `[V3] then` / `[V3] else` — if/then/else（redirect なし）
- `[V4] x` / `[V4] after-redirect` — 正常パスへの redirect を挟む
- `[V5] x` / `[V5] then2` / `[V5] else` — 空変数へのガード付き redirect（前回 surface しなかった form の再現）

判定：

- どの V の marker が**欠けるか**で、surface を殺す要素が特定できる
  - V3 欠落 → `if/then/else` 構造が原因
  - V4 欠落 → redirect 記述が原因（正常パスでも）
  - V5 だけ欠落 → 空変数へのリダイレクト記述が原因
  - 全部出る → 前回の非 surface は別の一時的要因だった
