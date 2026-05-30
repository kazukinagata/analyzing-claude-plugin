---
name: run-pretooluse-probe
description: Triggers the plugin-level PreToolUse hooks by running a sentinel bash command, to test (via session export) whether Cowork runs PreToolUse hook commands through cmd.exe or a POSIX shell, and whether the inline block pattern actually blocks the bash tool.
user-invocable: true
---

# run-pretooluse-probe

Cowork の **PreToolUse hook の実行シェル**と **inline block パターンの有効性**を調べる probe です。PreToolUse hook の stdout は context に surface しないため、詳細な観測はセッションのエクスポートで行います。このスキルの役割は hook を発火させるトリガーを引くことです。

## 手順

1. 次の bash コマンドを **1 回だけ** 実行してください（plugin-level PreToolUse hook を発火させるトリガーです。他の余計な bash は実行しないこと）:

   ```
   echo PROBE_BLOCK_TRIGGER probe-pretooluse-shell-check
   ```

2. 実行結果を一言で報告してください:
   - コマンドが **block された / 拒否された** → 「**blocked**」
   - コマンドが **実行できて出力が出た** → 「**ran**」＋ その出力

3. 報告後、ユーザがこのセッションをエクスポートし、hook の実行記録（各 `PRE_*` エントリの stdout / stderr / exit code）を解析します。

なお、この probe を入れている間は bash 実行のたびに hook が走ります。`$(cat)` などを含むエントリが環境によってはエラー行を出すことがありますが、これは観測対象（cmd.exe か POSIX かを分けるデータ）なので想定どおりです。

## 判定の見方（エクスポート解析側）

**PreToolUse の実行シェル（主目的）**
- `PRE_HOME=$HOME` が literal、`PRE_DQ="double-quoted"` で quote が残る、`PRE_NUL=$NO_SUCH_VAR_EXPECT_EMPTY` が literal → **cmd.exe**（SessionStart と同じ。§5 の inline block 例は要修正）
- `PRE_HOME=/home/...`、quote 除去、`PRE_NUL=` が空 → **POSIX シェル**（SessionStart と挙動が違う＝新発見。hook event ごとに実行シェルが違うことになる）
- `PRE_BASH_HOME=/home/...` は `bash -c` 経由の WSL 確認（CLI/Cowork どちらでも展開されるはずの control）

**inline block パターンの有効性（§5 の検証）**
- 手順1 が **blocked** → `tool_input=$(cat); ... | grep -q ... && echo '{block}'` が機能した（POSIX 系シェル）
- 手順1 が **ran** → block パターンが動かず素通り（cmd.exe 系で `$(cat)`/`|`/`grep` が機能せず）。記事 §5 の inline block 例は Cowork では効かない、の証拠
- session-export の `PRE_S5_PATTERN` エントリの stderr / exit code で、なぜ動いた/動かなかったかを裏取りする

## CLI baseline（任意）

`claude --plugin-dir ./cowork-pretooluse-shell-probe` で起動し、bash を 1 回走らせれば CLI 側の挙動が取れる。CLI では PreToolUse hook は `/bin/sh` 実行なので `PRE_HOME` は実パス、quote 除去、`PRE_NUL` 空になるはず（= 正常系リファレンス）。
