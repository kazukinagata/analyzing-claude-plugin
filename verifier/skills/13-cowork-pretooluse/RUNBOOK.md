# RUNBOOK: 13-cowork-pretooluse

## 検証内容

| 環境 | plugin-level PreToolUse | tool 名 |
|---|---|---|
| CLI | Bash matcher で block 成立 → `TEST_BASH_OK_MARKER` は出ない | `Bash` |
| Cowork | どの matcher でも block 不発 → `TEST_BASH_OK_MARKER` が出る | `mcp__workspace__bash` |

## 事前準備（CLI 用）

`verifier/hooks/hooks.json` の `PreToolUse` セクションに、block.sh を呼ぶエントリを追加する必要があります（plan で言及した 4 matcher パターン）。本リポジトリ scaffolding ではまず `log.sh pretool-bash` だけが入っているので、CLI で block を試したい時は別 plugin 経由が必要、または hooks.json を一時編集してください。

## CLI 手順

```sh
cd /home/kazukinagata/projects/analyzing-claude-plugin
. scripts/_env.sh
claude --plugin-dir ./verifier
```
プロンプトで：
```
/verifier:13-cowork-pretooluse
```

## Cowork 手順

`docs/cowork-runbook.md` 参照（zip upload して 13 を slash 起動）。

## 想定 verdict

- CLI: `TEST_BASH_OK_MARKER` が出る／hooks.log に `tag=pretool-bash` が記録される → finding と一致しないので別 probe（block 実装）が必要
- Cowork: `tool_name: mcp__workspace__bash` が transcript に出ているか、`pretool-mcp-workspace-bash` tag が hooks.log にあるか確認
