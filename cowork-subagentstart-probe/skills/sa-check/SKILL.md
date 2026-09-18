---
name: sa-check
description: SubagentStart hook の additionalContext 注入が Cowork でも動くかを実機検証する probe。sa-reporter subagent を起動し、subagent 側に SA-JSON / SA-MATCHED / SA-PLAIN が届いたかを報告させ、main session 側の SA-EXECLOG（hook が実際に走ったか）と突き合わせる。
user-invocable: true
---

# sa-check — SubagentStart additionalContext 注入の実機検証

このスキルは **4 手** で終わります。推測で埋めず、実際に出た文字列だけを書いてください。

## 手順

1. **baseline**：今の context に `SA-CTL` で始まる行があるか確認する（plugin の hook が
   そもそも surface しているかの土台確認）。出た値をそのまま控える。
2. **subagent を起動する**：`Agent` ツールで `subagent_type` に
   `cowork-subagentstart-probe:sa-reporter` を指定し、`run_in_background: false`、
   prompt は `Report the SA-* markers in your context.` とする。
   （このツール呼び出し自体が SubagentStart event のトリガー）
3. **subagent の返答を一字一句そのまま貼る**（4 行フォーマット）。
4. **main session 側**の context に `SA-EXECLOG` / `SA-STOP` で始まる行が出たか確認し、
   そのまま貼る。`SA-EXECLOG` は PostToolUse(Agent) hook が host 側の実行ログを
   再生したもので、**hook が走ったのに出力が捨てられた**のか、**event 自体が発火しなかった**
   のかを切り分ける唯一の証拠。

## 判定表

| subagent 側 | main 側 SA-EXECLOG | 結論 |
|---|---|---|
| `SA-JSON` あり | count ≥ 1 | **SubagentStart の additionalContext は Cowork でも届く**（本命の肯定） |
| `SA-JSON` 無し / `SA-PLAIN` あり | count ≥ 1 | hook は発火するが **JSON additionalContext は無視され、plain stdout だけが届く** |
| 両方無し | count ≥ 1 | **hook は実行されたが subagent へ何も注入されない**（出力が捨てられている） |
| 両方無し | count = 0 | **SubagentStart event が Cowork で発火しない**（または host 側 FS が hook↔hook で共有されない） |
| `SA-MATCHED` の有無 | — | matcher（agent 名スコープ）が SubagentStart で効くかどうか |
| `SA-CTL` が subagent 側にも出る | — | 注入ではなく **親 context の継承**を見ている可能性 → SA-JSON の有無で判断する |

## 記録すべきこと

- インストールできたか（validation failed が出たら、それ自体が結果）
- 上の 4 行 ＋ `SA-EXECLOG` 行 ＋ `SA-STOP` の有無
- どの判定セルに該当したか
- Code タブ / Cowork タブ どちらで実行したか、OS
