# RUNBOOK: 00-canary

## 目的

観測基盤（plugin-level hooks、skill frontmatter hook、log.sh、Bash tool 経由のファイル書き込み）が現バージョンで生きていることを確認する。**このスキルが PASS しない限り、後続 probe の verdict は信用できない**。

## 事前準備

1. `./scripts/capture-cli-help.sh` を実行済みであること（step 0 完了）
2. `findings/cli-help/STEP0-SUMMARY.md` を読んでおくこと

## 手順

```sh
# 1. 別 terminal で project root に移動
cd /home/kazukinagata/projects/analyzing-claude-plugin

# 2. 環境変数を export
. scripts/_env.sh

# 3. 対話 claude を起動（ephemeral 経路、marketplace 不要）
claude --plugin-dir ./verifier
```

claude が起動したら、最初のプロンプトで次を入力：

```
/verifier:00-canary
```

Claude が以下を実行することを承認：
- `mkdir -p` で findings dir 作成
- `printf` でログ書き込み
- `ls -la` `cat` `tail` で log 確認

完了したら `exit` で抜ける。

## 観察ポイント（人間目視）

1. **対話セッション中に `/verifier:00-canary` の補完が出るか** → これで step 0e（`--plugin-dir` 経由の slash 名前空間）の判定が分かる
2. Claude が表示する `cat probe.log` の出力に `tag=alive-check` と `tag=fm-registered` の**両方**が含まれているか
3. Claude が表示する `tail hooks.log` の出力に `tag=session-start`、`tag=user-prompt-submit`、`tag=pretool-bash` 各タグが含まれているか
4. `parallel-{a,b,c}` の log 行が hooks.log に出ているか（§1.10 の事前確認も兼ねる）

## 自動判定（./scripts/assert.sh 00）

`findings/expected/00-canary.txt` の必須出現文字列を `findings/v.../<sid>/{hooks.log,probe.log}` から探す。

- 全て見つかる → **PASS**
- 一部欠ける → **PARTIAL**（report.md にどの観測経路が死んでいるか書く）
- alive-check 不在 → **CANARY-FAILED**（後続 probe の verdict は無効扱い）

## トラブルシュート

| 症状 | 仮説 | 対処 |
|---|---|---|
| `/verifier:00-canary` 補完が出ない | `--plugin-dir` で slash 名前空間が変わった | install-marketplace.sh 経由で正式 install して再試行 |
| probe.log 不在 | `CLAUDE_PROJECT_DIR` 未設定 or skill body が走らない | Claude に「step 1 をもう一度実行して」と再依頼 |
| hooks.log 不在 | log.sh が走らない（permission, shebang） | `bash verifier/hooks/log.sh test` 直接実行で確認 |
| `tag=fm-registered` 不在 | skill frontmatter hook が登録されない | research §1.8 の "登録タイミング" 仕様変更の可能性。FAIL として記録 |
| `tag=alive-check` 不在 | Claude が skill body を走らせなかった | LLM 挙動の問題。slash 起動を slash で再試行 |
