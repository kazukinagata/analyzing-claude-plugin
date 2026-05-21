# Methodology

このリポジトリの観測方法と再現性確保のルール。

## 1. 観測の原則

- **観測**：何を実行したら何が記録／表示されたか（再現可能な事実）
- **解釈**：観測から導いた仕様の推定
- **判定**：研究との一致度を 6+1 verdict で表現

## 2. 検証スタイル

ユーザの選好：**不確定要素のある自動検証より手動検証を好む**。

このため：
- Claude を `--print` で動かして probe を回す自動化は採用しない
- 検証は **人間が `claude` 対話セッションを起動し、MASTER-RUNBOOK の指示通りに動かす**
- 自動化するのは **log の集約・解析・PASS/FAIL 判定** のみ（`scripts/assert.sh`）

## 3. ログフォーマット

すべての log エントリは：
```
[<probe-id> <iso-timestamp>] tag=<sub-step> <key>=[<value>] ...
```

例：
```
[01-BODY 2026-05-18T15:42:31+09:00] tag=alive-check
[01-BODY] CLAUDE_PLUGIN_ROOT=[(unset)]
[01-BODY] CLAUDE_CODE_ENTRYPOINT=[cli]
```

`(unset)` と `(empty)` を区別する：
- `(unset)`：env 変数が **export されていない**（パラメータ展開で何も返らなかった）
- `(empty)`：env 変数は export されているが空文字列

## 4. flock を入れる理由

§1.10 の並列発火により、複数 hook が同時に `hooks.log` に append する。flock なしだと書き込みが行入れ替わる／途切れる。`log.sh` は `flock -x 9` を取って排他制御する。

flock 不在環境では noop fallback が動くが、§1.10 の判定は SKIP される（report.md にも明示）。

## 5. CLAUDE_SESSION_ID による log 分離

probe 09 は slash 起動と自然文起動の log を分離する必要があり、probe 18 はクロスチャットの log を分離する必要がある。

`log.sh` は `${CLAUDE_SESSION_ID}` で出力ディレクトリを分ける：
```
findings/v2.1.143/
├── <sid1>/{hooks.log,probe.log}     # session A
├── <sid2>/{hooks.log,probe.log}     # session B
└── ...
```

`CLAUDE_SESSION_ID` が hook env で取れない場合は `findings/session-marker.txt` から source する（fallback）。

## 6. verdict 6+1 種

| verdict | 意味 |
|---|---|
| PASS | finding が現バージョンでも有効（log と expected が一致） |
| FAIL | finding が変化している証拠あり |
| PARTIAL | subclaim の一部のみ変化 |
| UNKNOWN | 観測が成立せず判定不能（alive-check 不在等） |
| DOC-ALIGNED | finding は変化したが docs と一致する方向（バグ修正） |
| CANARY-FAILED | probe 00 が PASS せず、後続全 probe の verdict は信用できない |
| MANUAL-OK / MANUAL-NG | 自動判定不可、人間目視で判定 |

## 6.1 観測ノートの書き場所

`findings/v<VERSION>/observations.md` に probe ごとの研究差分を**逐次追記**する。`assert.sh` の機械的 verdict（PASS/FAIL/…）だけでは捕捉できない以下の情報を残す：

- research §X.Y のどの subclaim が成立／失効したか
- 新たに分かった挙動（research に書かれていなかった env や flag）
- v2.1.146 固有のバグ class（例：skill body の `$1` pre-substitution）
- plan / SKILL 設計に対する改訂提案

`findings/v*/observations.md` と `findings/v*/report.md` は `.gitignore` の exception 対象なので、log は ignore したまま観測 note と verdict 集計だけが git に残る。

## 7. 観測前 invariant 確認（canary）

すべての probe は alive-check tag を log に出してから本検証を行う。これにより：
- alive-check 不在 → UNKNOWN（観測自体失敗、finding 変化と区別）
- alive-check あり + expected 不一致 → FAIL（finding 変化）

probe 00 が PASS していなければ後続全 probe は CANARY-FAILED 扱い。

## 8. ~/.claude 副作用の許容範囲

`CLAUDE_CONFIG_DIR=$(pwd)/findings/claude-home/` で**大半の書き込みを project-local に閉じる**。ただし以下は隔離保証外：
- `~/.claude/.credentials.json`（OS keychain fallback）
- `~/.claude/projects/<hash>/`（session 履歴、CLAUDE_CONFIG_DIR 経由でも可能性あり）
- `~/.claude/file-history/`
- OS keychain（macOS Keychain / Linux secret service）

縮退目標：「`~/.claude/plugins/` 配下と `~/.claude/settings.json` の `pluginConfigs` セクションを汚さない」。各 probe 実行後、以下で漏れを検出可能：

```sh
find ~/.claude -newer findings/claude-home/.before-marker -not -path '*/projects/*' 2>/dev/null
```

## 9. probe 設計の交絡条件対策

- **probe 10 (parallel)**：sleep を 200ms / 400ms / 0ms と差を OS スケジューラ粒度より大きく。start_ns / end_ns を両方記録
- **probe 11/12 (block)**：MASTER-RUNBOOK で「12 を slash で先に起動 → 11 を自然文で起動」の順序を厳密化（slash 起動は PreToolUse:Skill 不発、§1.9）
- **probe 09 (slash vs natural)**：2 セッション運用で CLAUDE_SESSION_ID 分離。各セッション 1 prompt で完結させて他 input 混入を防ぐ
- **probe 17 (bash mount)**：CLI で `find /sessions` が空ヒットすることを許容する設計。`${CLAUDE_SKILL_DIR}` fallback を持つ

## 10. 再実行可能性

`./scripts/reset.sh current` で `findings/v<VER>/` を削除、`./scripts/reset.sh --all` で全バージョン削除。expected と claude-home はデフォルト保持。
