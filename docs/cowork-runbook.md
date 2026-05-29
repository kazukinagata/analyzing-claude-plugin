# Cowork Manual Runbook

Cowork（Claude Desktop の cloud VM 機能）での実機検証手順。CLI と異なり完全自動化はできず、Desktop UI 操作と zip upload が必要。

## 1. zip パッケージング

```sh
cd /path/to/analyzing-claude-plugin
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

### 22-cowork-mp-script — GUI marketplace install 経路の検証

§1〜§21 までは全て **zip upload 経路**での検証だった。Claude Desktop の Cowork には別経路として **「GitHub の marketplace を直接追加して、その中の plugin を install する」GUI フロー**が存在する。zip upload と env / 置換挙動が同じかは未検証なので、それを切り分ける。

#### 0. 前提

- 本リポジトリが GitHub にあること（既存：`github.com/kazukinagata/analyzing-claude-plugin`、default branch `main`）
- ローカルでの変更（cowork-mp-script-probe/ と marketplace.json への追記）が **default branch に push されていること**（marketplace fetch は default branch を見る）

```sh
cd /path/to/analyzing-claude-plugin
git push origin main
```

#### 1. CLI baseline（推奨）

Cowork に上げる前に、CLI で marker.sh が起動することを確認しておく：

```sh
. scripts/_env.sh
claude --plugin-dir ./cowork-mp-script-probe
```

prompt：
```
/cowork-mp-script-probe:show-mp-script
```

CLI で期待される結果：
- `MP_SCRIPT_CONTROL=static_marker_no_var` が出る
- `MP_SCRIPT_ECHO_BARE=/...absolute path...` （env シェル展開で実パス）
- `MP_SCRIPT_ECHO_SQ=${CLAUDE_PLUGIN_ROOT}` （single-quote で literal、事前置換は走らない、§1.2 と一致）
- `MP_SCRIPT_MARKER form=topbare ...` が出る（script 起動成功、`ROOT_ENV=[/...]`）
- `MP_SCRIPT_MARKER form=bashbrace ...` が出る（同上）

CLI で marker 2 行とも出れば probe そのものは健全。Cowork に進む。

#### 2. Claude Desktop / Cowork：GUI marketplace add

Claude Desktop アプリで：
1. Settings → Plugins → Marketplaces セクション
2. 「Add marketplace」相当のボタン
3. リポジトリ指定：`kazukinagata/analyzing-claude-plugin`（GitHub owner/repo）
4. 確認ダイアログを承認

Marketplace listing に `verifier-mp` が見え、その中に `cowork-mp-script-probe` を含む plugin 一覧が並ぶ。

#### 3. plugin install（GUI）

`cowork-mp-script-probe` を選んで install。**zip upload 用の UI 経路ではなく、marketplace listing からの install ボタン**を必ず使う。

#### 4. Cowork session 起動 + probe 実行

新しい Cowork session を開く（または既存 session を resume）。SessionStart hook が発火するはずなので、session 開始直後の context にすでに `MP_SCRIPT_*` 系の行が含まれている。

```
/cowork-mp-script-probe:show-mp-script
```

skill が context 内の MP_SCRIPT_* 行を抽出して提示してくれる。

#### 5. 比較ポイント（zip 経路 baseline との差分）

zip upload 経路で既知の挙動（§2.1 / §2.2）：
- `MP_SCRIPT_CONTROL` → 出る
- `MP_SCRIPT_ECHO_BARE` → **literal `${CLAUDE_PLUGIN_ROOT}`**（top-level で `$VAR` 展開が抑止されるため、空ではなく literal）
- `MP_SCRIPT_ECHO_SQ` → literal `${CLAUDE_PLUGIN_ROOT}`
- `MP_SCRIPT_MARKER form=topbare` → **行が出ない**（`${CLAUDE_PLUGIN_ROOT}` literal で path 不在 → exec 失敗、stderr は surface しない）
- `MP_SCRIPT_MARKER form=bashbrace` → **行が出ない**（`bash -c` 内では `$CLAUDE_PLUGIN_ROOT` の env 展開は走るが env が空、結果 `/hooks/marker.sh` を起動しようとして exec 失敗）

GUI marketplace install で **挙動が同じ**なら：plugin install path に依存せず Cowork 共通の制約、§2.1 / §2.2 を一般化できる。

GUI marketplace install で **挙動が違う**なら：例えば `MARKER form=topbare` が出る、`ROOT_ENV` に値が入る、等。zip 経路だけの bug / 仕様の可能性。findings に書き分ける必要あり。

**実観測（2026-05-29, GUI marketplace install）**：5 観測点すべてが zip 経路と完全一致。`install path 非依存、Cowork 共通制約`として確定。`docs/team-report.md` §2.2 末尾に追記済み。

#### 6. findings 記録

`findings/v<version>/cowork-mp-script.md` に観測した 5 行（無い場合は「無し」と明記）と各変種の verdict を記録。可能なら `marketplace_name` 等の OTel event 情報も拾う（§B.3）。

### 23-cowork-mp-disambig — hook runtime model の最終切り分け

`cowork-mp-script-probe` の観測（§2.2 モデル訂正）で「Cowork の hook command は `bash -c` を経由した通常 POSIX 展開を**経ていない**らしい」までは確定したが、**実装が (a) shell bypass か (b) bash -c with $-escape か**は ECHO_BARE/ECHO_SQ だけでは切り分けられない。`cowork-mp-disambig-probe` は double-quote と `$HOME`（env に値が確実にある変数）と unset 変数の 3 軸で最終切り分けを行う。

#### 1. CLI baseline

```sh
. scripts/_env.sh
claude --plugin-dir ./cowork-mp-disambig-probe
```

prompt：
```
/cowork-mp-disambig-probe:show-mp-disambig
```

CLI 期待値（参考、通常 shell 経由）：
- `MP_DA_DQ=double-quoted`（quote 消費）
- `MP_DA_DQ_INNER=hello-middle-world`
- `MP_DA_HOME=/home/...`
- `MP_DA_HOME_BRACE=/home/...`
- `MP_DA_PATH=/usr/local/sbin:...`
- `MP_DA_NUL=`（空、unset env は empty）
- `MP_DA_BASH_HOME=/home/...`

#### 2. GUI marketplace install + Cowork 実行

`docs/cowork-runbook.md` §22 と同じ手順で `cowork-mp-disambig-probe` を install → 新規 Cowork chat → `/cowork-mp-disambig-probe:show-mp-disambig`。

#### 3. 解釈

8 観測点で以下のように verdict が決まる：

| 観測 | 意味 |
|---|---|
| `MP_DA_DQ="double-quoted"` literal | shell parser が動いていない（または `"` が escape されている） |
| `MP_DA_DQ=double-quoted` | shell parser が動いている → モデル (b) 強化 |
| `MP_DA_HOME=$HOME` literal | env 展開ゼロ → モデル (a) 強化 |
| `MP_DA_HOME=/home/...` 等の実値 | env 展開あり → モデル (b)、ただし `$` escape は限定的 |
| `MP_DA_NUL=` empty | env 展開はあるが値が無いので empty。モデル (b) 強化 |
| `MP_DA_NUL=$NO_SUCH_VAR_EXPECT_EMPTY` literal | env 展開ゼロ → モデル (a) 強化 |

ECHO_BARE で env 展開ゼロが既に確定しているので、ここで HOME / NUL が **literal** で残れば「shell bypass モデル (a) 」が決定打。逆に HOME が実値、NUL が empty で resolve したら「`$` escape は `CLAUDE_PLUGIN_ROOT` だけにかかっている」可能性があり、もっと込み入った escape ルールを推定する必要が出る。

#### 4. session-export での裏取り

§22 と同じく Claude Desktop の Export Session → zip 中 `<sessionId>.jsonl` を `jq` で grep。各 hook entry の `command` / `stdout` / `exitCode` を確認すれば context 経由より厳密に観察できる（context 経路で missing しても zip には残る、§2.2bis）。

#### 5. 実観測（2026-05-29, GUI marketplace install）

8 観測点すべて `hook_success exit=0`。結果：

| 観測点 | stdout | verdict |
|---|---|---|
| `MP_DA_CONTROL` | `static_marker_no_var` | hook surface ✓ |
| `MP_DA_DQ` | `"double-quoted"` literal | shell parse 無し |
| `MP_DA_DQ_INNER` | `hello-"middle"-world` literal | 同上 |
| `MP_DA_HOME` | `$HOME` literal | **HOME は universally set なのに展開ゼロ。決定打** |
| `MP_DA_HOME_BRACE` | `${HOME}` literal | 同上、brace 形でも展開ゼロ |
| `MP_DA_PATH` | `$PATH` literal | 同上 |
| `MP_DA_NUL` | `$NO_SUCH_VAR_EXPECT_EMPTY` literal | unset でも literal、shell ならここは empty 化けるはず |
| `MP_DA_BASH_HOME`（bash -c wrap） | `/home/kazukinagata` 実値 | 内側 bash でだけ POSIX 展開 |

**結論**：「Cowork 自体で top-level command の shell parse は走らない」が**確定**（HOME / PATH / NUL の 3 重 literal）。実装が (a) shell bypass か (b) bash -c + aggressive escape か**観測上は区別不能**だが、実用効果は完全同一。詳細は `docs/team-report.md` §2.2 末尾に追記。

#### 6. 追加観測（2026-05-29, WSL2 実行環境の再確認）

hook が WSL2 で実行されている事実を新規 chat で再確認するため、`bash -c` でラップした 4 マーカーを追加（top-level の `$PATH` は literal で WSL パスを拾えないため）：

| 観測点 | stdout | verdict |
|---|---|---|
| `MP_DA_BASH_HOME`（再掲） | `/home/kazukinagata` | WSL2 Ubuntu のホーム |
| `MP_DA_BASH_HOST` | `LAPTOP-BKGB6100` | WSL2 既定 hostname（=Windows マシン名） |
| `MP_DA_BASH_PATH` | `/usr/lib/wsl/lib`・`/mnt/c/Users/knaga/...` を含む | **WSL2 限定パス。決定打** |
| `MP_DA_BASH_WSL_LIB` | `absent)'` のみ（prefix 欠落） | **probe 作成ミス**。`$()`+`&&`+`||`+quote の混在を Cowork の top-level 処理が分断したアーティファクト。WSL の有無とは無関係 |
| `MP_DA_BASH_MNT_C` | 同上 | 同上 |

**結論**：`MP_DA_BASH_PATH` に `/usr/lib/wsl/lib` が含まれる時点で「hook は WSL2 Ubuntu で実行された」は確定（`WSL_LIB`/`MNT_C` 行は壊れたが PATH で代替できるので再実行不要）。ただしこれは Windows+WSL2 という本検証機固有の事実であり、Cowork の WSL 依存を意味しない（`docs/team-report.md` 冒頭「検証環境の前提」§2.0）。`$()`/`||` を含む複雑な hook command は Cowork で壊れる、という副次的な注意点も得られた。

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
