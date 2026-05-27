---
name: envfile-check
description: Reads ENVFILE_MARKER set via CLAUDE_ENV_FILE by the SessionStart hook, and surfaces diagnostic markers, to test whether the env-file mechanism reaches the Bash tool on Cowork and whether multi-statement hooks surface.
user-invocable: true
---

# envfile-check

3 つの SessionStart hook が走りました：単一 echo の診断（`[DIAG-ENVFILE]`）、複数文 echo（`[DIAG-MULTI]`）、env file への書き込み（echo 無し）。次の bash を実行してください。

```bash
echo "BODY host=$(hostname)"
echo "BODY ENVFILE_MARKER=[${ENVFILE_MARKER:-(unset)}]"
```

実行後、context にある以下の行を**すべて**そのまま貼ってください（無いものは「無し」）：

- `[DIAG-ENVFILE] CLAUDE_ENV_FILE=[...] host=...`（単一 echo。surface 実績のある形）
- `[DIAG-MULTI] line1` / `[DIAG-MULTI] line2`（複数文 echo）

判定：

- `[DIAG-ENVFILE]` が出て `CLAUDE_ENV_FILE=[/某パス]` → CLAUDE_ENV_FILE は host hook で set されている（伝播しないだけ = (b)）
- `[DIAG-ENVFILE]` が出て `CLAUDE_ENV_FILE=[]`（空） → host hook で未設定（= (a)）
- `[DIAG-MULTI]` が両行出る → 複数文 hook も surface する
- `[DIAG-MULTI]` が出ない → 複数文 hook は surface しない（前回 surface しなかった理由）
- `BODY ENVFILE_MARKER` → 機構が Bash tool に届くか
