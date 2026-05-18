# Check Matrix

研究 §番号 ↔ probe skill ↔ subclaim ↔ verdict 6 種 の対応表。

## 略号

- `[CLI]` = CLI で自動 / 半自動チェック可
- `[CW]` = Cowork 実機検証必須
- 「verdict 6+1 種」は `findings/README.md` 参照

## マトリクス

| § | finding | probe | subclaim | 検証経路 |
|---|---|---|---|---|
| §1.1 / §3.1 | env propagation 3-tier 非対称 | 01 | plugin-level に DATA / frontmatter に DATA なし / Bash tool に PLUGIN_ROOT なし | [CLI] |
| §1.2 / §3.2 | `${VAR}` substitution allowlist | 02 | skill body 経路で SKILL_DIR / SESSION_ID 置換、PROJECT_DIR は literal | [CLI] |
| §1.2 (validator) | skill frontmatter で `${CLAUDE_PLUGIN_DATA}` を書くと validator block | 02 + verifier-violator/02b | install error に `CLAUDE_PLUGIN_DATA` `plugin-only` `skill hooks` のうち 2 単語以上が出現 | [CLI] |
| §1.2 (Bad substitution) | skill frontmatter で `${user_config.KEY}` を書くと `/bin/sh` Bad substitution | 02 + verifier-violator/02c | install error or hook stderr に `Bad substitution` | [CLI] |
| §1.3 | hook 実行は `/bin/sh` (dash) | 03 | `BASH_VERSION=[]` / `RANDOM=[]` / `[[` syntax error | [CLI] |
| §1.4 | `sensitive: true` の値が env 平文 | 04 | hooks.log に `CLAUDE_PLUGIN_OPTION_API_SECRET=[secret-xyz-CANARY]` | [CLI] |
| §1.5 | userConfig prompt trigger 4 ルート | 05 | install/enable silent、`/plugins` UI prompt、disable→enable 条件付き、未設定 hook error | [CLI] 半自動 |
| §1.6 | marketplace cache vs source path | 06 | `CLAUDE_PLUGIN_ROOT != cache_path`（PASS）または `==`（DOC-ALIGNED） | [CLI] |
| §1.7 | skill body subst は invoke 経路のみ | 07 | Read 経路は literal / invoke 経路は substituted | [CLI] 半自動 |
| §1.8 | skill frontmatter hook は invoke 後に登録 | 08 + 08b | SessionStart + `once: true` 不発、PreToolUse は invoke 後発火、自スキル block 不可 | [CLI] |
| §1.9 / §6.2 | slash 経由は Skill tool 通らない | 09 | slash sid に `tag=pretool-skill` なし、自然文 sid にあり | [CLI] |
| §1.10 | hook array 内並列発火 | 10 | parallel-c-end が a-end より早い、a-end が b-end より早い | [CLI] |
| §1.11 | 二層 trust モデル | (設計指針) | probe なし、設計文書化 | — |
| §2.1 | Cowork SessionStart resume 再発火 | 19 | hooks.log に `source=resume` 行が追加 | [CW] |
| §2.2 | Cowork userConfig 欠落 | 05 + cowork-runbook | UI 自体無し、disable→enable / `/plugins` 不在、silent skip | [CLI]+[CW] |
| §2.3 | Cowork hook validation 差 | 20 | UserPromptExpansion 入り plugin → Cowork で `Plugin validation failed`、CLI で具体エラー | [CW] |
| §2.4 | Cowork bash = `mcp__workspace__bash` | 13 | tool_name の確認、`pretool-mcp-workspace-bash` 発火 | [CW] |
| §2.5 | Cowork plugin-level PreToolUse 死亡 | 13 | block されず `TEST_BASH_OK_MARKER` が出る | [CW] |
| §2.6 / §7.10 / §7.11 | Cowork parser whitelist | 14 | `&&` `||` `cat`/`printf`/`sh -c` 分断、`echo` `bash -c` だけ通る | [CW] |
| §2.7 | Cowork hook file I/O 死亡 | 15 | `/tmp/file-io-canary-*.txt` が見えない | [CW] |
| §2.8 / §7.9 | Cowork path 3 形式 | 16 | BODY_SUBST = Win path, HOOK_SUBST = MSYS, HOOK_ENV = Linux mount | [CW] |
| §2.9 | Cowork 接続フォルダ + `request_cowork_directory` | 21 | outputs/ RW、plugin dir RO、承認後フォルダ RW | [CW] |
| §2.10 | Cowork bash mount + bundled script | 17 | Pattern A 動く / Pattern B 失敗 / `mkdir -p $DATA` ゴミ生成 | [CW] |
| §2.11 | Cowork DATA session 分離 | 18 | 別 chat で marker 見えず、ROOT は同値 | [CW] |
| §2.12 | `CLAUDE_CODE_REMOTE` 空 (Cowork) | 18 | `CLAUDE_CODE_REMOTE=[(unset)]` または `=[]` | [CW] |
| §9 | OTEL 計測 | (本リポジトリ範囲外) | — | — |
| §10 | docs vs 実測 早見表 | 横串（A-O 各 row が 01–18 に分散） | report.md にバージョン別の差分メモ | — |
| §11 | ハーネス設計指針 | (設計文書) | — | — |
| §12 | 未解決事項 | 18（DATA 永続性）、その他は本検証で解消 | — | — |

## verdict 解釈ガイド

| verdict | 意味 | report.md での扱い |
|---|---|---|
| **PASS** | research の finding が現バージョンでも成立 | research-summary に変更不要 |
| **FAIL** | finding が変化（壊れた／実装が変わった） | research-summary に "v2.1.143 で変化あり" メモ |
| **DOC-ALIGNED** | docs と整合する方向に変化（バグ修正）。research の前提が更新される | research-summary に "v2.1.143 で docs と一致するようになった" |
| **PARTIAL** | subclaim の一部のみ変化 | report.md に subclaim 単位で記録 |
| **UNKNOWN** | 観測が成立せず判定不能 | runbook を見直し、再実行 |
| **CANARY-FAILED** | probe 00 が PASS せず、後続全 probe の verdict が信用できない | 観測基盤を直してから再実行 |
| **MANUAL-OK / MANUAL-NG** | 自動判定不可、人間目視で判定 | report.md に人間判定の根拠を付記 |
