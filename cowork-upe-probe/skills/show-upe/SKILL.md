---
name: show-upe
description: Surfaces UPE_PROBE_* marker lines to test whether the plugin-level UserPromptExpansion hook fires on Cowork. Invoking this skill via slash is itself the trigger; compares against UserPromptSubmit and SessionStart controls.
user-invocable: true
---

# show-upe

この skill を **slash で起動した**（`/cowork-upe-probe:show-upe` と入力した）こと自体が UserPromptExpansion hook のトリガーです（UserPromptExpansion は slash 経由でのみ発火する event）。直前の context（SessionStart / UserPromptSubmit / UserPromptExpansion hook の stdout として注入されたもの）から、次のプレフィックスで始まる行を**一字一句そのまま**貼ってください。見当たらないものは「無し」と明記してください。

- `UPE_PROBE_SESSIONSTART=` — SessionStart hook（plugin がロードされ hook の stdout が surface する基盤確認）
- `UPE_PROBE_PROMPTSUBMIT=` — UserPromptSubmit hook（slash でも発火する control。stdout は context に入る）
- `UPE_PROBE_EXPANSION=` — UserPromptExpansion hook（**今回の主目的**。slash 起動で発火するか）

## 判定の見方

- `UPE_PROBE_EXPANSION=fired` が出た → **UserPromptExpansion は Cowork でも発火する**（従来「CLI のみ」とした結論の更新）
- `UPE_PROBE_EXPANSION` 無し かつ `UPE_PROBE_PROMPTSUBMIT=ok` は出る → **UserPromptExpansion だけ発火しない**（UserPromptSubmit は出るので「hook が surface しない」ではなく event 固有。従来結論「CLI のみ」が Cowork でも成立）
- 両方無し かつ `UPE_PROBE_SESSIONSTART=ok` も無し → plugin hook がそもそも surface していない（基盤側の問題。別 chat で再試行）

## プラットフォーム別の注意

- **Windows Cowork**：この plugin は UserPromptExpansion event を含むため、**インストール/有効化時に `Plugin validation failed` で reject される可能性が高い**（§2.3）。その場合は「install できなかった（validation failed が出た）」を Windows の結果として記録。発火検証はインストールできた場合のみ。
- **macOS Cowork**：validator が通れば（Mac は CLI 寄りなので通る可能性あり）、上の発火判定を行う。

報告フォーマット：3 マーカーの有無（出た値も）＋ どの判定セルに該当したか＋ install できたか（特に Windows）。
