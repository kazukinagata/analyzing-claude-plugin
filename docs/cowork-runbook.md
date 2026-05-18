# Cowork Manual Runbook

Cowork（Claude Desktop の cloud VM 機能）での実機検証手順。CLI と異なり完全自動化はできず、Desktop UI 操作と zip upload が必要。

## 1. zip パッケージング

```sh
cd /home/kazukinagata/projects/analyzing-claude-plugin
. scripts/_env.sh
./scripts/package-cowork.sh
```

以下の 3 zip が生成される：
- `findings/v2.1.143/verifier-cowork.zip` — メイン probe プラグイン（`UserPromptExpansion` event は strip 済み）
- `findings/v2.1.143/verifier-violator-userpromptexpansion.zip` — probe 20a 用
- `findings/v2.1.143/verifier-violator-uppercase-name.zip` — probe 20b 用

## 2. Cowork セッションを開く

Claude Desktop アプリを起動 → 新しい Cowork セッションを作成。

## 3. verifier を upload

Cowork UI の「Plugins」または「Settings」セクションから zip upload：
1. `findings/v2.1.143/verifier-cowork.zip` を選択
2. enable / activate
3. **userConfig 入力 UI が表示されるか目視**（§2.2 の判定材料。期待：UI 自体無し）

## 4. Cowork 専用 probe を順に起動

各 probe を Cowork chat の slash 起動で実行：

### 13-cowork-pretooluse

```
/verifier:13-cowork-pretooluse
```

`TEST_BASH_OK_MARKER` が probe.log に tee されるはずだが、これは CLI / Cowork どちらでも出る（default の hooks.json には block 仕掛けが入っていないため）。**CLI baseline で plugin-level PreToolUse の block を実際に観察**したい場合は、以下の手順で `hooks-block.json` を一時的に差し替える：

```sh
# CLI side, before invoking 13:
cp verifier/hooks/hooks.json verifier/hooks/hooks.json.bak
cp verifier/hooks/hooks-block.json verifier/hooks/hooks.json
. scripts/_env.sh && claude --plugin-dir ./verifier
# /verifier:13-cowork-pretooluse → TEST_BASH_OK_MARKER は OUTPUT されないはず
# 完了後:
mv verifier/hooks/hooks.json.bak verifier/hooks/hooks.json
```

Cowork では block 試行 hook が一切発火しないので、`hooks-block.json` を仕込んでも `TEST_BASH_OK_MARKER` がそのまま出力される（§2.5 と一致）。

### 14-cowork-parser

事前準備：parser-test 用 hooks.json variant を一時的に差し替えてから zip 化：

```sh
cp verifier/hooks/hooks.json verifier/hooks/hooks.json.bak
cp verifier/hooks/hooks-parser-tests.json verifier/hooks/hooks.json
./scripts/package-cowork.sh   # 新しい verifier-cowork.zip が parser-tests 入りで生成される
mv verifier/hooks/hooks.json.bak verifier/hooks/hooks.json
```

その zip を Cowork にアップロードしてセッション開始（SessionStart で parser-test エントリが発火する）。

```
/verifier:14-cowork-parser
```

`findings/parser-tests.log` または probe.log の出力で、`PARSER_TEST_AND` / `PARSER_TEST_OR` が抜けていれば §2.6 と一致。

### 15-cowork-file-io

```
/verifier:15-cowork-file-io
```

`/tmp/file-io-canary-*.txt` が `ls` で見えないことを確認。`15-FM-hook` は probe.log に出るはず（hook 自体は呼ばれた証拠）。

### 16-cowork-path-forms

```
/verifier:16-cowork-path-forms
```

probe.log の `BODY_SUBST` / `HOOK_SUBST` / `HOOK_ENV` の値を比較。Windows / MSYS / Linux の 3 形式の path であれば §2.8 と一致。

### 17-cowork-bash-mount

```
/verifier:17-cowork-bash-mount
```

Pattern A は動く、Pattern B は失敗するはず。

### 18-cowork-data-isolation（多ステップ）

ステップ 1（chat A）：
```
/verifier:18-cowork-data-isolation
```

marker_to_write の値を MASTER-RUNBOOK 18 セクションに**手で記録**。

ステップ 2（chat A で suspend/resume）：Claude Desktop のウィンドウフォーカスを 3 分外す → 戻る → 同じ chat で再度 `/verifier:18-cowork-data-isolation`。read_back が同じ marker であることを確認（同 chat = 永続）。

ステップ 3（chat B、新 chat）：同 project で新 chat を起動 → `/verifier:18-cowork-data-isolation`。read_back が chat A の marker と異なる（または不在）ことを確認（cross-chat 分離）。

### 19-cowork-resume

```
/verifier:19-cowork-resume
```

1st invoke して exit せず、3 分フォーカス外して戻る → 2nd invoke。hooks.log に `source=resume` 行があれば §2.1 と一致。

### 20-cowork-validation

以下の 2 zip を **別々に** Cowork にアップロードして、それぞれで `Plugin validation failed` が出るか目視：

1. `findings/v2.1.143/verifier-violator-userpromptexpansion.zip` — UserPromptExpansion 入り
2. `findings/v2.1.143/verifier-violator-uppercase-name.zip` — name が `Verifier-Violator-Uppercase`

CLI baseline は probe 20 SKILL.md 内で `claude plugin validate "$proj/verifier-violator-userpromptexpansion"` を回し、具体的なエラーメッセージ vs Cowork の generic メッセージを比較する。

### 21-cowork-connected-folder

```
/verifier:21-cowork-connected-folder
```

outputs/ への書き込みが成功、plugin dir への書き込みが失敗することを確認。`request_cowork_directory` 承認 UI が出るかを目視。

## 5. 結果記録

各 probe の結果を `findings/v2.1.143/cowork-report.md` に手書きで記録。テンプレート：

```markdown
# Cowork verification — v2.1.143

| probe | verdict | observation |
|---|---|---|
| 13-cowork-pretooluse | PASS | TEST_BASH_OK_MARKER が出力された |
| 14-cowork-parser | PARTIAL | ... |
| ... |
```

## 6. Cowork 用 findings の host 側コピー

Cowork VM 内の `findings/v2.1.143/<sid>/{hooks,probe}.log` を host にコピーするには：
1. Cowork UI で `outputs/` 配下にコピーすれば、Desktop 経由でホストにコピー可能
2. または Claude にお願いして `cp /sessions/<codename>/mnt/<project>/findings/... outputs/cowork-findings/` を実行してもらう

ホスト側 `findings/v2.1.143/cowork/` に展開してから `./scripts/assert.sh NN` を回す。
