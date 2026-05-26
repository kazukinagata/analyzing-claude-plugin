# MASTER-RUNBOOK

22 probe 分の手動検証手順を上から下に並べた本体ドキュメント。各 probe で何を打ち、何を観察し、`assert.sh` で何が返るかを記述。

**前提**：`docs/methodology.md` と `docs/check-matrix.md` を一読しておくこと。

## 表記

- 💻 = CLI 検証
- 🌐 = Cowork 実機検証必須
- ✋ = 完全手動（人間目視）
- 🤖 = `assert.sh` で自動判定

---

## 準備 (Step 0)

1. `./scripts/capture-cli-help.sh` を実行（v2.1.143 の CLI 構文・shell baseline 確定）
2. `findings/cli-help/STEP0-SUMMARY.md` を読む

## 00-canary 💻🤖 — 観測基盤の生存確認

**ここが PASS しない限り、後続の verdict は信用できない**

```sh
cd /path/to/analyzing-claude-plugin
. scripts/_env.sh
claude --plugin-dir ./verifier
```

プロンプト：
```
/verifier:00-canary
```

Claude が step 1 / step 2 の bash を承認実行。exit。

```sh
./scripts/assert.sh 00
```

期待 verdict：**PASS**。FAIL なら observation infrastructure が壊れている。

---

## 01-env-propagation 💻🤖 — env 伝播 3 階層

§1.1 / §3.1。

```sh
claude --plugin-dir ./verifier
```
プロンプト：`/verifier:01-env-propagation` → 完了 exit → `./scripts/assert.sh 01`

### 観察ポイント

- `[01-BODY] CLAUDE_PLUGIN_ROOT=[(unset)]` が出る（Bash tool subprocess に env が渡らない）
- `[01-FM] OPT_HELLO=[(empty)]` `OPT_SECRET=[(empty)]` が出る（frontmatter に OPTION が渡らない）
- hooks.log（plugin-level）に `CLAUDE_PLUGIN_DATA=[/...]` の実値あり

---

## 02-substitution-allowlist 💻🤖 — `${VAR}` 置換 allowlist

§1.2 / §3.2。

```sh
./scripts/install-marketplace.sh   # verifier-violator の install エラーを取るために必要
```

install.log を `findings/v2.1.143/install.log` で確認。`CLAUDE_PLUGIN_DATA` や `plugin-only` の文言を含むエラーが出ているはず。

次に：
```sh
claude --plugin-dir ./verifier
```
プロンプト：`/verifier:02-substitution-allowlist` → exit → `./scripts/assert.sh 02`

### 観察ポイント

- `[02-BODY] SUBST_ROOT=[/...]` 絶対 path に展開
- `[02-BODY] SUBST_PROJECT_DIR=[${CLAUDE_PROJECT_DIR}]` literal のまま
- install.log に `CLAUDE_PLUGIN_DATA` キーワードが出ているか

---

## 03-shell-binsh 💻🤖 — hook 実行は /bin/sh (dash)

§1.3。

```sh
claude --plugin-dir ./verifier
```
プロンプト：`/verifier:03-shell-binsh` → exit → `./scripts/assert.sh 03`

---

## 04-sensitive-leak 💻🤖✋ — sensitive 値の env 平文露出

§1.4。事前準備：`./scripts/install-marketplace.sh` 経由で `-s local` install されている場合、設定先は repo root の `.claude/settings.local.json`（gitignore 済み）。user scope (`-s user`) なら `findings/claude-home/settings.json`。実機で確認する path を `claude plugin list -v` 等で確定してから手書きする：

```json
{
  "pluginConfigs": {
    "verifier@verifier-mp": {
      "hello_message": "hello-from-cli-CANARY",
      "api_secret": "secret-xyz-CANARY"
    }
  }
}
```

または対話 claude セッションで `/plugins` を打って UI から入力（v2.1.143 で対話入力 UI が存在することは step 0e で確認済）。

```sh
claude --plugin-dir ./verifier
```
プロンプト：`/verifier:04-sensitive-leak` → exit → `./scripts/assert.sh 04`

### 観察ポイント

- hooks.log に `CLAUDE_PLUGIN_OPTION_API_SECRET=[secret-xyz-CANARY]` が平文で出る
- settings.json の中身（`pluginConfigs`）に `api_secret` が**書かれていない**こと（keychain 行きの可能性）

---

## 05-userconfig-trigger 💻✋ — userConfig prompt trigger 4 ルート

§1.5。**完全手動**。

1. `./scripts/install-marketplace.sh` 実行時の prompt 表示有無を目視（**期待：silent**）
2. settings.json から `pluginConfigs` を削除し、対話 claude で `/verifier:05-userconfig-trigger` 起動 → hook error が出るか目視
3. 対話 claude セッションで `/plugins` を打って UI 経由で入力できるか試す
4. plugin disable → enable で値入力 prompt が出るか試す

各ステップの結果を **MASTER-RUNBOOK のこの section にチェックボックス形式で記録**してください：

- [ ] 0. install: silent (期待通り) / prompt 表示 (finding 変化)
- [ ] 1. hook error: 出た (`Plugin option "..." isn't set.`) / 出ない
- [ ] 2. `/plugins` UI: 起動 / 非対応
- [ ] 3. disable → enable: prompt 出る（参照あり時）/ 出ない

最後に `./scripts/assert.sh 05`（自動判定可能なのは step 1 の hook error のみ）。

---

## 06-marketplace-cache 💻🤖 — cache vs source 実行パス

§1.6。事前：`./scripts/install-marketplace.sh` 実行済み。

```sh
claude --plugin-dir ./verifier   # ephemeral でも /verifier:06 起動可
```
プロンプト：`/verifier:06-marketplace-cache` → exit → `./scripts/assert.sh 06`

verdict 二択：
- `VERDICT=PASS (root != cache, ...)` → **PASS**
- `VERDICT=DOC-ALIGNED (root == cache, ...)` → **DOC-ALIGNED**

---

## 07-skill-body-subst 💻✋🤖 — invoke 経路と Read 経路の差

§1.7。**2 セッション**。

### A. Read 経路

```sh
claude --plugin-dir ./verifier
```
プロンプト：
```
verifier/skills/07-skill-body-subst/SKILL.md の中で "CHECK_LINE:" で始まる行をそのまま教えてください。
```

Claude の返答を `findings/v2.1.143/07a-read-response.txt` に paste。返答に literal `${CLAUDE_PLUGIN_ROOT}` を含むか目視（**期待：literal**）。

### B. invoke 経路

新セッション：`claude --plugin-dir ./verifier` → `/verifier:07-skill-body-subst` → exit。

```sh
./scripts/assert.sh 07
```

probe.log の `INVOKE_LINE: PLUGIN_ROOT_VALUE=/<abs>` を機械判定。

---

## 08-frontmatter-timing 💻🤖 — frontmatter hook 登録タイミング

§1.8。

```sh
claude --plugin-dir ./verifier
```
プロンプト：`/verifier:08-frontmatter-timing` → exit → `./scripts/assert.sh 08`

### 観察ポイント

- probe.log に `tag=alive-check` あり、`08-FM-SESSIONSTART unexpected fire` **なし**
- 後続 bash で `[08-FM-PreToolUse fired]` あり（invoke 後の発火確認）

---

## 08b-self-block-attempt 💻✋ — 自スキル block 不可

§1.8。

```sh
claude --plugin-dir ./verifier
```
プロンプト 1：`/verifier:08b-self-block-attempt`（初回 invoke）
- alive-check が出る = 自身の load は block されなかった

プロンプト 2：「`08b-self-block-attempt` をもう一度起動してください」（自然文）
- 2 度目は frontmatter hook が block する

exit。

---

## 09-slash-vs-natural 💻🤖 — slash 経由は Skill tool 通らない

§1.9 / §6.2。**2 セッション**。

### A. slash 経由

```sh
claude --plugin-dir ./verifier
```
プロンプト：`/verifier:09-slash-vs-natural` → exit。

### B. 自然文経由

```sh
claude --plugin-dir ./verifier
```
プロンプト：「`09-slash-vs-natural` という skill を起動してください」 → exit。

```sh
./scripts/assert.sh 09
```

両 sid の hooks.log を結合して `tag=pretool-skill`（自然文側にあるはず）と `tag=user-prompt-expansion`（slash 側にあるはず）を判定。

---

## 10-parallel-hook-firing 💻🤖 — array 内並列

§1.10。

```sh
claude --plugin-dir ./verifier
```
プロンプト：`/verifier:10-parallel-hook-firing` → exit → `./scripts/assert.sh 10`

### 観察ポイント

hooks.log の `tag=parallel-{a,b,c}-end` の ts 順序が「c < a < b」（sleep 通り）なら並列、「a < b < c」（array 順）なら順次実行 = finding 変化。

---

## 11/12-block ペア 💻🤖 — frontmatter PreToolUse:Skill で別 skill を block

§2.4 / §2.5。

```sh
claude --plugin-dir ./verifier
```

**厳密順序**：
1. 最初のプロンプト：`/verifier:12-block-self`（self-blocker の hook 登録）
2. 完了を待つ
3. 2 つ目のプロンプト：「`11-block-target` skill を起動してください」（**自然文**。slash だと PreToolUse:Skill 不発）
4. block が発火 → reason が表示される
5. exit

```sh
./scripts/assert.sh 11
./scripts/assert.sh 12
```

`11-BODY` が probe.log にあれば block 失敗。なければ block 成功。

---

## 13-cowork-pretooluse 💻🌐🤖 — Cowork plugin-level PreToolUse 死亡

§2.5 / §2.4。

### 💻 CLI baseline

```sh
claude --plugin-dir ./verifier
```
プロンプト：`/verifier:13-cowork-pretooluse` → exit → `./scripts/assert.sh 13`

### 🌐 Cowork

`docs/cowork-runbook.md` 参照。zip upload して `/verifier:13-cowork-pretooluse` 起動、`TEST_BASH_OK_MARKER` が出るか目視。

---

## 14-cowork-parser 💻🌐🤖 — Cowork parser whitelist

§2.6 / §7.10 / §7.11。

### CLI baseline と Cowork 用 zip は同じ swap で両対応

手順は **swap → CLI 起動 / Cowork zip 化 → restore** の順。

#### Step 1: parser-test variant に hooks.json を差し替え

```sh
cp verifier/hooks/hooks.json verifier/hooks/hooks.json.bak
cp verifier/hooks/hooks-parser-tests.json verifier/hooks/hooks.json
```

#### Step 2-A: CLI baseline 取得

```sh
claude --plugin-dir ./verifier
```
プロンプトで `/verifier:14-cowork-parser`。probe.log の "parser-tests.log (verbatim)" セクションに各 `PARSER_TEST_*` 文字列が出るか確認（hook が実際に書き込んだものだけが出るので、欠落 = 失敗パターン）。

#### Step 2-B: Cowork 用 zip を parser-test variant 入りで生成

```sh
./scripts/package-cowork.sh
```

`findings/v.../verifier-cowork.zip` に parser-test 入りの hooks.json が同梱される。これを Cowork にアップロードして `/verifier:14-cowork-parser` を起動、`PARSER_TEST_AND` / `PARSER_TEST_OR` が抜けることを目視。

#### Step 3: restore（必ず最後）

```sh
mv verifier/hooks/hooks.json.bak verifier/hooks/hooks.json
```

Cowork で AND / OR が absent ＝ §2.6 と一致（assert.sh は CLI baseline 用なので Cowork log に対して走らせると FAIL になるが、それ自体が finding）。

---

## 15-cowork-file-io 💻🌐🤖 — hook 内 file write が Cowork で届かない

§2.7。

CLI / Cowork 両方で `/verifier:15-cowork-file-io` 起動。CLI なら `/tmp/file-io-canary-*.txt` が見える。Cowork なら見えない。

---

## 16-cowork-path-forms 🌐🤖 — Cowork で path 3 形式

§2.8 / §7.9。Cowork 専用観察。

`/verifier:16-cowork-path-forms` 起動して probe.log を比較。BODY_SUBST / HOOK_SUBST / HOOK_ENV の 3 形式が異なるか目視。

---

## 17-cowork-bash-mount 🌐🤖 — bundled script の起動パターン

§2.10。Cowork で `/verifier:17-cowork-bash-mount` 起動。

- Pattern A（find → cd → bash scripts/say-hi.sh）：Cowork でも動く
- Pattern B（bash `${CLAUDE_SKILL_DIR}/scripts/say-hi.sh`）：Cowork で No such file or directory

CLI baseline：両方とも動く（`${CLAUDE_SKILL_DIR}` が Linux path）。

---

## 18-cowork-data-isolation 🌐🤖✋ — DATA cross-chat 分離

§2.11 / §2.12。

### Cowork chat A

`/verifier:18-cowork-data-isolation` を起動して marker 書き込み。**marker 文字列をここに記録**：

```
chat A marker: ______________________________
```

### chat A 内で suspend/resume テスト

Claude Desktop のフォーカスを 3 分外して戻る → `/verifier:18-cowork-data-isolation` 再起動 → read_back の値が同じであることを確認（同 chat 内 = 永続）。

### chat B（同 project の新 chat）

`/verifier:18-cowork-data-isolation` 起動 → read_back が**異なる** marker または「ファイル不在」エラーを返すことを確認（Cowork = 分離）。

---

## 19-cowork-resume 🌐✋🤖 — SessionStart resume 再発火

§2.1。Cowork 専用。

`/verifier:19-cowork-resume` 起動（1st invoke）→ probe.log に `19-FM-still-registered` 出る → exit。

3 分フォーカス外して resume → `/verifier:19-cowork-resume`（2nd invoke）。

hooks.log に `source=resume` の追加行があるか、probe.log に `19-FM-still-registered` が **2 つ** 出ているか確認。

---

## 20-cowork-validation 💻🌐🤖 — Cowork validation 差

§2.3。CLI で probe SKILL.md が `claude plugin validate $proj/verifier-violator-userpromptexpansion` と `$proj/verifier-violator-uppercase-name` を順に走らせる。それぞれの出力（CLI 側の具体的なエラー文言）が probe.log に tee される。

Cowork 側は `./scripts/package-cowork.sh` 実行後、生成された `verifier-violator-userpromptexpansion.zip` と `verifier-violator-uppercase-name.zip` を**別々に** Cowork にアップロードして、それぞれで `Plugin validation failed` の generic エラーになるか目視。

CLI（具体）と Cowork（generic）の差が §2.3 の finding。

```sh
claude --plugin-dir ./verifier
```
プロンプト：`/verifier:20-cowork-validation` → exit → `./scripts/assert.sh 20`

---

## 21-cowork-connected-folder 🌐✋ — 接続フォルダと request_cowork_directory

§2.9。Cowork 専用、ほぼ手動目視。

`/verifier:21-cowork-connected-folder` 起動 → outputs/ への書き込み OK / plugin dir への書き込み FAIL を確認。`request_cowork_directory` で任意フォルダ承認 → 承認後 RW 可を確認。

---

## 全体集計

22 probe を回したら：

```sh
./scripts/assert-all.sh
```

`findings/v2.1.143/report.md` に PASS/FAIL/DOC-ALIGNED/PARTIAL/UNKNOWN/CANARY-FAILED/MANUAL-OK の集計テーブルが出る。
