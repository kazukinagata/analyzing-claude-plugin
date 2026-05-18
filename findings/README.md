# findings/

実行結果と固定 expected の集約。

## ディレクトリ

- **`claude-home/`**: `CLAUDE_CONFIG_DIR` が指す project-local な claude home。実行時生成、`reset.sh --claude-home-only` で削除可
- **`cli-help/`**: `capture-cli-help.sh` の出力。実装の最初に1回だけ生成
- **`expected/`**: 各 probe の expected 文字列。バージョンに依らない（commit 対象）
- **`v<VERSION>/`**: バージョン別の実行結果。`hooks.log` / `probe.log` / `report.md` / `<sid>/...`

## 命名規則

- ファイル名：`<probe-id>.txt` 形式（例: `01-env-propagation.txt`）
- `v$(claude --version | awk '{print $1}')` を VERSION として使う

## expected ファイルのフォーマット

```
# コメント行
@<log-file-name>           # この section の検索対象 (hooks.log / probe.log / install.log)
<必須出現文字列1>           # この文字列が grep -F で1回以上 hit するべき
<必須出現文字列2>
!<出現してはいけない文字列>   # ! prefix で否定
```

複数の `@<file>` を並べると section が切り替わる。

## verdict 6+1 種

- `PASS` — finding が現バージョンでも有効
- `FAIL` — finding が変化している証拠あり
- `DOC-ALIGNED` — finding は変化したが docs と一致する方向（バグ修正された）
- `PARTIAL` — subclaim の一部のみ変化
- `UNKNOWN` — 観測が成立せず判定不能
- `CANARY-FAILED` — canary probe 00 で観測基盤自体が破綻
- `MANUAL-OK/NG` — 自動判定不可、ユーザ目視で判定
