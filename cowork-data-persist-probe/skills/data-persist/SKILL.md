---
name: data-persist
description: Mac Cowork で、plugin-level SessionStart hook(host 側)から $CLAUDE_PLUGIN_DATA に書いた値が「別の chat session を跨いで」残るかを検証する probe。書き込み＆読み戻しは hook(persist.sh)側で行い、その結果は SessionStart の stdout として context に出る。この skill body は対比用に「VM Bash 側から DATA が見えるか／hook が書いたファイルを読めるか」を確認する。
user-invocable: true
---

# data-persist

**問い**: Mac Cowork で `CLAUDE_PLUGIN_DATA` に永続化した値は、Cowork のセッションを跨いで参照できるか？

## 重要な前提（なぜ hook 側で書くのか）

既存観測 OBS-3 のとおり、Mac Cowork では **`CLAUDE_PLUGIN_DATA` は plugin-level hook(host 側)にだけ set** され、
**skill body / VM Bash tool には unset**。よって「DATA に書いて読み戻す」操作自体が **body では不可能**で、
本 probe の write+read-back は **`hooks/persist.sh`（SessionStart hook, host 側）** が行う。
その出力（`DP_*` 行）は SessionStart の stdout として context に注入されるので、そこから判定する。

## 手順（クロスセッション・プロトコル）

この probe の本体は SessionStart hook なので、**chat を開くたびに自動で 1 回 append + read-back** が走る。

1. **session #1**: この plugin を有効化した新しい chat を開く。SessionStart context に出る `DP_*` 行を控える。
   - 期待: `DP_PRIOR_COUNT=[0]`、`DP_AFTER_WRITE_TOTAL=[1]`。
2. **session #2**: いったん **別の新しい chat session** を同じプロジェクトで開く（resume ではなく新規 chat）。
   - 永続化されるなら: `DP_PRIOR_COUNT=[1]`、`DP_PRIOR sid=<session#1 の sid> ...` の行が見え、`DP_AFTER_WRITE_TOTAL=[2]`、
     かつ `DP_DATA_HASH` が session#1 と **同じ数値**。
   - 分離されるなら: `DP_PRIOR_COUNT=[0]` のまま（毎回まっさら）、`DP_DATA_HASH` が session ごとに **変わる**。
3. （任意）**resume の対比**: 同じ chat を suspend→resume すると SessionStart:resume が再発火する。
   resume で count が増え prior が見えるが新規 chat で見えない、なら「同一 chat 内では永続／chat を跨ぐと分離」。

## body 側の対比チェック（VM から DATA は触れるか）

以下の bash を **Bash tool** で実行して、VM 側の状態を記録してください（hook 側の結論の裏取り）。

```bash
echo "BODY_DATA=[${CLAUDE_PLUGIN_DATA:-(unset)}]"
echo "BODY_HOST=$(hostname)"
# hook(host)が書いたであろう host パスを VM から読めるか試す（読めないはず）
echo "--- try to read the host marker from the VM ---"
ls -la "${CLAUDE_PLUGIN_DATA}/persist-marker.log" 2>&1 | head -2
cat "${CLAUDE_PLUGIN_DATA}/persist-marker.log" 2>&1 | head -3
```

## 報告フォーマット

- session #1 の `DP_DATA_PATH` / `DP_DATA_HASH` / `DP_PRIOR_COUNT` / `DP_AFTER_WRITE_TOTAL`
- session #2（別 chat）の同じ 4 値、特に **`DP_PRIOR_COUNT` と `DP_PRIOR` 行が session#1 の sid を含むか**、`DP_DATA_HASH` が一致するか
- body 側 `BODY_DATA`（unset のはず）と、VM からの `ls`/`cat` の成否

## 判定

- session#2 で `DP_PRIOR_COUNT>=1` かつ session#1 の sid が `DP_PRIOR` に見える かつ `DP_DATA_HASH` 一致
  → **DATA は Cowork セッションを跨いで永続する**。
- session#2 でも `DP_PRIOR_COUNT=0`／`DP_DATA_HASH` が毎回変わる
  → **DATA は chat session ごとに分離（永続しない）**。
- どちらにせよ `BODY_DATA=(unset)` で VM からは読めない見込み（OBS-3/OBS-11 と整合）。
