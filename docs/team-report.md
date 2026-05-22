# Claude Code Plugin 作成ガイド — CLI と Cowork の挙動差分まとめ

## この文書の目的

Claude Code（Anthropic 公式 CLI / Claude Desktop アプリ）には plugin 機構があり、プロジェクト固有の skill（指示書）や hook（バックグラウンド処理）を定義できる。ところが公式 docs には書かれていない仕様や、ドキュメントと挙動が矛盾する箇所が多数あり、plugin を実装すると「動くはずなのに動かない」「CLI では動くのに Cowork（Claude Desktop の VM 実行モード）では動かない」といった事象に頻繁にぶつかる。

本資料は、それらの落とし穴を実機検証で洗い出した結果をチーム共有用にまとめたもの。検証対象は **Claude Code v2.1.146（CLI 側）+ v2.1.146-148（Cowork 側）**、2026 年 5 月時点。

- **第 1 章** — CLI で plugin を作るときに知っておくと事故を防げる知識
- **第 2 章** — 第 1 章で取り上げた論点について Cowork では何が変わるか

詳細な観測ログと改訂提案は `findings/v2.1.146/observations.md` および `findings/v2.1.146/report.md` を参照。

---

## 用語の整理（最低限）

| 用語 | 意味 |
|---|---|
| **Plugin** | `.claude-plugin/plugin.json` と `hooks/` `skills/` を持つディレクトリ単位。複数 skill / 複数 hook を 1 つの plugin にまとめる |
| **Skill** | `skills/<name>/SKILL.md` で定義される指示書。`user-invocable: true` を付けると `/<plugin>:<skill>` の slash command でユーザが起動できる |
| **Hook** | 特定のイベント（SessionStart / UserPromptSubmit / PreToolUse 等）で発火するシェルコマンド。2 種類ある：<br>① **plugin-level hook** = `hooks/hooks.json` に定義<br>② **skill frontmatter hook** = SKILL.md の YAML frontmatter に定義 |
| **Bash tool** | Claude（LLM）が呼び出すツール。実行時はシェルプロセスを起動する。Skill body 内のコードブロックも結局これ経由 |
| **userConfig** | plugin.json で宣言する設定項目。ユーザが入力した値が `${user_config.KEY}` や env var として hook に渡る |
| **CLI** | `claude` コマンドで起動するターミナル版 |
| **Cowork** | Claude Desktop アプリ（Windows）で動く VM 実行モード。本資料の検証で **実体は host-adjacent な VM + virtio-fs**（つまり「クラウド」ではなくユーザ機の隣接 VM）であることが判明している |

---

# 第 1 章：CLI で plugin を作るときに知っておくべき知識

## 1.1 環境変数の伝播は 3 階層で非対称

plugin の実行プロセスには 3 種類あり、それぞれに渡される env var が違う。これを知らずに「plugin-level hook では使えた変数が、skill 内 bash では空になる」ような事故が起きる。

| 環境変数 | plugin-level hook | skill frontmatter hook | Bash tool subprocess |
|---|:---:|:---:|:---:|
| `CLAUDE_PLUGIN_ROOT` | ✅ | ✅ | ❌ |
| `CLAUDE_PLUGIN_DATA` | ✅ | ❌ | ❌ |
| `CLAUDE_PROJECT_DIR` | ✅ | 未確認 | ❌ |
| `CLAUDE_PLUGIN_OPTION_<KEY>` | ✅（機密値含む） | ❌ | ❌ |
| `CLAUDE_CODE_ENTRYPOINT` 等 | ✅ | ✅ | ✅ |

**実装ソースの根拠**：`src/utils/hooks.ts` の `if (pluginId)` ガードと `SkillHookMatcher` 型に pluginId 欠落、という構造。意図的な設計。

**実用上の含意**：
- Skill 内の bash から plugin install dir を参照したい場合は `${CLAUDE_PLUGIN_ROOT}` を **skill body の置換経由**で取得する（後述 1.7）。env var には期待しない
- ユーザ設定値を hook に渡したいなら **plugin-level hook** で扱う。skill frontmatter hook には値が来ない

## 1.2 `${VAR}` の事前置換は文脈ごとに効く範囲が違う

Claude Code 本体は hook command や skill body の文字列を実行前に `${VAR}` 形式でスキャンして置換する（Claude Code 事前置換）。一方、シェル展開（`$VAR`）は実行時に OS シェルが行う。両者が混在して非対称な挙動になる。

| 記法 | plugin-level hook command | skill frontmatter hook command | skill body markdown |
|---|:---:|:---:|:---:|
| `${CLAUDE_PLUGIN_ROOT}` | ✅ 置換 | ✅ 置換 | ✅ 置換 |
| `${CLAUDE_PLUGIN_DATA}` | ✅ | ❌ **validator block**（後述） | ✅ |
| `${user_config.KEY}` | ✅ | ❌ literal で `/bin/sh` に渡る → `Bad substitution` エラー | 未検証 |
| `${CLAUDE_SKILL_DIR}` | ❌ | 未検証 | ✅（SKILL.md の dirname） |
| `${CLAUDE_SESSION_ID}` | 未検証 | 未検証 | ✅（session UUID） |
| `${CLAUDE_PROJECT_DIR}` | ✅ | 未検証 | ❌ literal のまま |

skill frontmatter hook に `${CLAUDE_PLUGIN_DATA}` を書くと plugin install 時の validator が以下で reject する：

```
Hook command references ${CLAUDE_PLUGIN_DATA} but only ${CLAUDE_PLUGIN_ROOT}
is available for skill hooks (${CLAUDE_PLUGIN_DATA} is plugin-only).
```

**実用上の落とし穴**：
- `${user_config.KEY}` を skill frontmatter hook に書くと、validator は通すが実行時に `/bin/sh` が `Bad substitution` で死ぬ。**skill frontmatter で userConfig を参照しない**
- `${CLAUDE_PROJECT_DIR}` は skill body 内では literal のまま。実体を欲しいなら hook 経由で書き出すか、bash で `$(pwd)` 等を使う

## 1.3 hook の実行シェルは `/bin/sh`（WSL/Ubuntu では dash）

bash 想定で書くと事故る。具体例：

| 書いた構文 | 何が起きるか |
|---|---|
| `[[ "$X" = "y" ]] && echo ok` | `/bin/sh: 1: [[: not found` |
| `${PWD^^}`（大文字化） | `Bad substitution` |
| `read -a array` | `read: bad option: -a` |
| `$RANDOM` | dash では空文字列に展開 |
| `date +%N` | 環境依存（dash でも動くが macOS は別） |

**実用上の対策**：
- bash 固有の構文を使いたい場合は **必ず `bash -c '...'`** で wrap する
- POSIX sh で書ける範囲に留めるのが安全

## 1.4 `sensitive: true` は保存先を分けるだけ、ランタイムは平文で env に出る

userConfig で `sensitive: true` フラグを付けると、設定値は `~/.claude/settings.json` ではなく OS keychain や `~/.claude/.credentials.json` に保存される。**ところがランタイムでは `CLAUDE_PLUGIN_OPTION_<KEY>` env var に平文で plugin-level hook に渡る**。コードコメントには「hooks run the user's own code, same trust boundary as reading keychain directly」と明記されており、意図的な設計。

**実用上の含意**：
- `sensitive: true` を信用して「他の plugin から読まれない」と思ってはダメ
- plugin-level hook で API secret 等を扱う場合、その hook command 自体が信頼境界
- ログに env をダンプする処理を入れる際は、機密値が混ざる可能性を踏まえてマスクする

## 1.5 userConfig 入力 UI の trigger ルールが複雑

「`/plugins` UI から enable した時に入力フォームが出ない」「`disable → enable` でも prompt が出ない」といった事象がよく報告される（GitHub issues #39455 / #39827 で "dead config" と呼ばれている）。

| 操作 | prompt 表示 |
|---|---|
| `claude plugin install` / `enable`（CLI シェル） | ❌ silent |
| `/plugins` UI → Configure options（手動） | ✅ |
| `/plugins` UI → disable → enable | プラグインのどこかで `${user_config.KEY}` が参照されており、かつ値が未設定の場合のみ ✅ |
| 参照あり + 未設定で hook が走った場合 | hook error `Plugin option "X" isn't set.` |

**実用上の対策**：
- 単に「`/plugins` で入力 UI が出る」と信じて任せると、参照されていない userConfig は **永久に未設定のまま**になる
- README で「初回 install 後は `settings.json` を直接編集して値を入れてください」と明示する、または skill body で値の有無をチェックして促す

## 1.6 marketplace cache と実行パスは別物

公式 docs は「marketplace plugin は `~/.claude/plugins/cache/` にコピーされて、そこから実行される」と書いているが、**ローカル marketplace の場合 `CLAUDE_PLUGIN_ROOT` は source ディレクトリを指す**。cache へのコピーはされるが、hook 実行には使われない。

**実用上の含意**：
- 開発中の plugin を `claude plugin marketplace add ./my-plugin` で登録して install したあと、`./my-plugin/` を編集すると即座に動作に反映される（cache をクリアする必要なし）
- 配布版で「cache が古い」「源を編集しても効かない」と思ったら、まず `CLAUDE_PLUGIN_ROOT` の値を確認する

## 1.7 skill body の `${VAR}` 置換は invoke 時のみ

SKILL.md の本文に書いた `${CLAUDE_PLUGIN_ROOT}` 等は、**skill が invoke されて Claude の context に load される瞬間**に Claude Code 本体が置換する。一方、ユーザや別の Claude が Read / Grep ツールで SKILL.md を**ファイルとして読んだ場合は literal のまま**。

確認方法：
- 同じ skill について「`CHANGELOG.md のパスはどこと指定されている？」と質問 → literal `${CLAUDE_PLUGIN_ROOT}/CHANGELOG.md` が返る
- 「skill を起動して、最初に CHANGELOG.md のパスを echo して」と指示 → 絶対パスが返る

**実用上の含意**：
- Skill 内 bash で `${CLAUDE_PLUGIN_ROOT}` を使うのは OK（invoke 経路）
- Skill のドキュメント本文に「`${CLAUDE_PLUGIN_ROOT}/foo.txt` を見てください」と書いて、別の skill から Read tool で読ませると literal が見えてユーザが混乱する。**ファイルパスを生で書きたい場合は事前置換を意識**

## 1.8 skill frontmatter hook は「一度 invoke した後」に登録される

これは強烈な落とし穴。skill frontmatter hook は、その skill が一度起動された後に有効化される。つまり：

- `SessionStart` + `once: true` を skill frontmatter に書いても **session 開始時には未登録なので発火しない**
- 自スキルの起動を skill frontmatter hook で block しようとしても **hook が load 後に登録されるので止められない**
- 一度 invoke された skill の frontmatter hook は、**`claude` プロセスが終了するまで** 後続の全 tool 呼び出しで発火し続ける（CLI の場合）

**実用上の含意**：
- 「skill 起動時の準備処理」は **plugin-level hook** に書く。skill frontmatter には書かない
- 「特定の他 skill を block」したい場合は、自分が一度 invoke される必要があるので、ユーザに「先にこの skill を起動してください」と促すフローが必須

## 1.9 slash 起動と自然言語起動で発火する hook が違う

ユーザが skill を起動する経路は 2 つあり、それぞれ Claude Code 内部の挙動が違う。

| 観測項目 | 自然言語経由 | slash 経由 |
|---|:---:|:---:|
| `Skill` tool が呼ばれる | ✅ | ❌ |
| `PreToolUse:Skill` 発火 | ✅ | ❌ |
| `UserPromptSubmit` 発火 | ✅ | ✅ |
| `UserPromptExpansion` 発火（CLI のみ）| ❌ | ✅ |

slash 経由は内部的に prompt テンプレート展開になり、Skill tool を経由しない。「`/foo:bar` で起動された時だけ PreToolUse:Skill hook が動かない」という事象はここに起因する。

**実用上の対策**：
- 起動経路に依存しない検知が欲しいなら、`UserPromptSubmit` で prompt 文字列を見る or 両経路の hook を組み合わせる
- 「skill が起動したら必ず ○○ を実行」を担保したい場合、skill body 内の bash 冒頭に書くのが最も確実

## 1.10 同じ hook 配列内のエントリは並列で走る

hooks.json 内で同じイベントに対して複数の command を array で並べた場合、それらは **並列に起動される**（配列順に逐次ではない）。観測すると、array order と log 書き込み順が逆転する。

**実用上の対策**：
- 同じファイルに書き込む処理を並列で複数走らせると race condition が起きる。`flock` で排他制御するか、書込先ファイルを分ける
- 「hook A の出力を hook B が読む」前提の設計はダメ。順序保証なし

## 1.11 skill 間 block は frontmatter `PreToolUse:Skill` で可能

ある skill が起動された時に別の skill を起動しようとするのを block する経路は：

- 自分が一度 invoke 済みの skill の frontmatter hook で `PreToolUse:Skill` matcher を別 skill 名にして JSON `{"decision":"block","reason":"..."}` を返す
- これは CLI / Cowork どちらでも動く（後述するように Cowork で plugin-level の PreToolUse は無効化されているが、frontmatter の PreToolUse:Skill は生存している）

**実用上の落とし穴**：
- block 対象 skill を **slash 経由** (`/foo:bar`) で起動された場合、上述 1.9 により Skill tool を経由しないので block 不発になる
- 自然言語経由（「`bar` を起動して」）の方しか確実に止められない

## 1.12 二層 trust モデル：skill は低信頼、plugin-level hook は高信頼

Claude Code の plugin 設計には明示的な信頼境界の二層構造がある（実装ソースコメントから読み取れる）：

| 役割 | 主体 | 信頼度 |
|---|---|---|
| ユーザ／Claude が叩く入り口（指示書） | **skill** | 低（SKILL.md 1 枚で持ち込み可、env も限定的） |
| 永続的な裏方処理（state・MCP・LSP・監視・ガードレール） | **plugin-level hook / MCP server** | 高（plugin 作者を信頼してインストール） |

これが §1.1 〜 §1.4 の非対称（hook には env / 機密値が来るが skill には来ない、等）の根拠。

**実用上の含意**：
- 機密値や永続的状態は **plugin-level hook で扱う**。skill body には絶対渡さない
- skill 単体で「強い権限」を持たせるべきではない。skill は plugin の hook と協調動作させる設計が望ましい

---

# 第 2 章：上記の論点について Cowork では何が変わるか

## 2.0 大前提：Cowork の architecture model

第 2 章を読む前提として、Cowork の実体を把握しておく必要がある。今回の検証で判明した model：

- **Cowork は「remote クラウド VM」ではない**。ユーザの Windows 機上で動く **host-adjacent な VM**（おそらく WSL/Hyper-V 系のスタック上で Anthropic がスポーンする隣接 VM）
- **VM とホストは virtio-fs / FUSE bind mount で filesystem を共有**している。`/sessions/<codename>/mnt/outputs/` 等はホストの `C:\Users\<user>\AppData\Roaming\Claude\.../outputs/` を bind mount したもの
- **plugin-level hook はホスト側（local Claude Desktop / WSL Ubuntu）で実行される**。`/sessions/` ディレクトリすら見えない、ホストの PATH (`/mnt/c/Users/...` 等) で動いている
- **Bash tool（実名 `mcp__workspace__bash`）は cloud VM 側で実行される**。hostname は literal `claude`
- **同一ユーザの全 chat は同じ VM を共有**。chat 単位で Linux user account を切り、POSIX permission で cross-chat isolation を実装
- `/sessions/` 配下には過去 3 ヶ月分・175 個の chat sandbox dir が累積していた（CLI session も `cli-<hex>` 形式で同居）

この split が以下の章で説明する挙動差分を全て統一的に説明する。

## 2.1 環境変数の伝播（§1.1 の Cowork 版）

CLI では plugin-level hook と skill frontmatter hook には `CLAUDE_PLUGIN_ROOT` 等が SET されていた。**Cowork ではこれが UNSET になっている**（regression）。

検証コード：
```bash
# Cowork hook の中で
bash -c "echo CLAUDE_PLUGIN_ROOT=$CLAUDE_PLUGIN_ROOT"
# → CLAUDE_PLUGIN_ROOT=  （空）
```

Bash tool subprocess に env が来ないのは CLI と同じ。さらに **`CLAUDE_CODE_ENTRYPOINT` も Cowork の Bash tool では UNSET**（CLI では `=cli` が来る）。

**実用上の含意**：
- Cowork で plugin-level hook から plugin install dir を参照したいなら **`${CLAUDE_PLUGIN_ROOT}` 置換**を使う必要あり（env var 経由はもう動かない）
- ただし後述 2.2 の通り、Cowork では `${VAR}` 置換も top-level command では機能しない。**結局 hook 内で plugin path を取得する手段がほぼ消失している**
- CLI と Cowork を分岐したいなら `hostname` 値（`claude` なら Cowork、それ以外なら CLI）か `CLAUDE_CODE_ENTRYPOINT` の有無で判定する

## 2.2 `${VAR}` 置換と shell expansion（§1.2 / §1.3 の Cowork 版）

これが最大の落とし穴。Cowork の plugin-level hook command は **二段階の実行モード**に分かれている：

| hook command の書き方 | 実行モード | `$VAR` / `${VAR}` の扱い |
|---|---|---|
| **top-level** `echo X` | literal text emission（shell プロセス起動なし）| `$VAR` も `${VAR}` も**完全に展開されない、literal 文字列のまま** |
| **`bash -c "..."` で wrap** | 実 bash subprocess 起動 | フル POSIX 展開（`$VAR` も `${VAR}` も期待通り） |

検証例（PATH を 5 通りで参照）：
```
echo EXP_TOP_DOLLAR=$PATH         → "$PATH" (literal)
echo EXP_TOP_BRACE=${PATH}        → "${PATH}" (literal)
bash -c "echo EXP_BASH_DOLLAR=$PATH"   → 実際の PATH 値
bash -c "echo EXP_BASH_BRACE=${PATH}"  → 実際の PATH 値
echo EXP_CONTROL_LITERAL=hello_world   → "hello_world" (literal、変数なし)
```

研究 v2.1.119 では「3 種類の path 形式 (Windows / MSYS / VM Linux mount) に化ける」とされていた `${CLAUDE_PLUGIN_ROOT}` が、v2.1.146-148 では **literal `${CLAUDE_PLUGIN_ROOT}` のまま** context に出てくる。理由はこの「top-level = literal emission」モデル。

**実用上の対策**：
- Cowork hook command で path を組み立てたい場合は **必ず `bash -c "..."` で wrap**
- 単純な定数 echo（変数なし）は top-level でも OK
- top-level command で `${...}` を書くと「動作確認しても期待した値が context に出ない、literal が出る」という事象になる。最初に踏みがちな罠

ただし朗報もある：研究 v2.1.119 で「Cowork では `bash -c "true && echo X"` の `&&` が outer parser に分断されて動かない」とされていたが、**v2.1.146-148 では `&&` `||` が `bash -c` 内で正常に動く**ようになった（DOC-ALIGNED）。改善された箇所。`printf` 等の echo/bash 以外の builtin は依然 reject される。

## 2.3 hook 実行シェルとシェル機能（§1.3 の Cowork 版）

CLI の hook 実行シェルは `/bin/sh`（dash）だった。Cowork は前述の通り「top-level は shell プロセスなし、`bash -c` で wrap した時だけ実 bash」という二段階モデル。

**実用上の対策**：
- bash 固有構文は `bash -c '...'` 内なら安全に書ける
- top-level command は echo の literal emission しか使えない、と割り切る

## 2.4 sensitive userConfig（§1.4 の Cowork 版）

Cowork には **そもそも userConfig UI が無い**。`/plugins` コマンド自体が存在せず、disable→enable のような操作も silent skip される。設定値が必要な plugin は Cowork で実質使えない。

**実用上の対策**：
- Cowork 対応 plugin を作る場合、**userConfig に依存しない**設計にする
- どうしても設定が要るなら、初回起動時に Claude に「ユーザに API key を聞いてください」と指示し、その値を session-scope の context に持つ（永続化は §2.7 の通り Cowork では不可）

## 2.5 userConfig trigger（§1.5 の Cowork 版）

§2.4 の通り、Cowork では trigger 経路がすべて死んでいる。CLI で確認されていた「`/plugins` UI から入力」「disable→enable で参照あり&未設定なら prompt」のいずれも Cowork では発生しない。

加えて、Cowork で `${user_config.KEY}` を含む SessionStart hook の配列を仕込むと、参照 entry だけが **silent skip** される（CLI なら hook error が出る経路と差別化されている）。

## 2.6 marketplace cache（§1.6 の Cowork 版）

Cowork には marketplace 概念そのものが無い。zip を Claude Desktop UI に upload する経路のみ。ローカル開発フローは「zip を再生成して再 upload」のループになる（重い）。

**実用上の対策**：
- Cowork での反復開発は CLI と比べて遅い。**CLI で reasonable に動くところまで詰めてから Cowork upload する**
- ただし後述 §2.13 の通り Cowork validator は CLI より厳しいので、CLI 通過 ≠ Cowork install 可能。CI に Cowork 実機 upload テストを組み込む必要がある

## 2.7 skill body の `${VAR}` 置換（§1.7 の Cowork 版）

skill body 内の `${CLAUDE_PLUGIN_ROOT}` `${CLAUDE_PLUGIN_DATA}` 置換は **Cowork でも機能する**。ただし置換される値は **ホスト Windows 側の絶対パス**（例：`C:/Users/knaga/AppData/Roaming/Claude/local-agent-mode-sessions/.../rpm/plugin_<id>/`）。

これを Bash tool（cloud VM 側で動く）で `bash "C:/Users/.../scripts/say-hi.sh"` のように使うと **`No such file or directory`** で失敗する。cloud VM の filesystem には Windows path が存在しないため。

**実用上の対策**：

| やりたい操作 | Cowork での書き方 |
|---|---|
| bundled script を Bash tool から起動 | `${CLAUDE_PLUGIN_ROOT}` は使わず、`find /sessions -path '*/skills/<name>' -type d` で cloud VM 側の mount path を localize してから cd + 相対 path |
| `${CLAUDE_PLUGIN_DATA}` への永続化 | できない。§2.8 参照 |
| Windows path を bash で `mkdir -p` | **危険**：bash は `:` を path separator として解釈しないので、`mkdir -p "C:/foo"` は **`$PWD/C:/foo` というゴミディレクトリを silent に作る**。必ずガードを入れる |

## 2.8 hook と Bash tool は完全に別の filesystem（§1.7 の派生）

Cowork architecture が原因で、**plugin-level hook が書いたファイルは Bash tool 側からは見えない**。

理由：
- plugin-level hook はホスト Windows / WSL Ubuntu で実行される
- Bash tool は cloud VM で実行される
- 両者は別の filesystem namespace

検証：
```bash
# hook 内で（ホスト側で実行される）
echo "marker" > /tmp/canary.txt
echo "marker" > "${CLAUDE_PLUGIN_DATA}/canary.txt"
```

Bash tool で：
```bash
ls /tmp/canary.txt
# → No such file or directory
ls "${CLAUDE_PLUGIN_DATA}/canary.txt"
# → No such file or directory
```

**実用上の含意**：
- Cowork で「hook が状態を持って、後で skill が読む」というよくあるパターンは動かない
- 状態を渡す手段は **hook の stdout が additionalContext として Claude の文脈に注入される** 経路のみ。これは session-scope（同一 chat 内）でしか有効ではなく、永続化にも使えない

## 2.9 skill frontmatter hook の登録タイミング（§1.8 の Cowork 版）

CLI では「一度 invoke した skill の frontmatter hook は `claude` プロセス終了まで生存」だった。Cowork では：

- skill frontmatter hook は **1 プロンプト内のみ有効**（VM suspend/resume で reset される）
- 同一 chat 内で window を非アクティブにして 3 分以上放置 → 戻ると skill を再 invoke するまで frontmatter hook 不発

**実用上の対策**：
- Cowork で長期的な guard を仕掛けたいなら frontmatter hook ではなく plugin-level hook を使う（ただし §2.10 の通り plugin-level PreToolUse block は無効化されている）
- 「user の bash 試行を guard したい」系の plugin は Cowork で実質機能不能

## 2.10 plugin-level PreToolUse block の無効化

CLI では plugin-level `PreToolUse` hook で `{"decision":"block","reason":"..."}` を返せば Bash tool 等を止められた。**Cowork ではこれが完全に死亡**。

検証：matcher を `"Bash"` / `"Skill"` / `".*"` / `"mcp__workspace__bash"` の 4 通り全て試した結果、JSON `decision: block` でも `exit 2` でも block されず、skill body の `echo TEST_BASH_OK_MARKER` が普通に実行された。

**実用上の含意**：
- 「危険な bash コマンドを plugin が事前に止める」系の guard は Cowork で動かない
- skill frontmatter の `PreToolUse:Skill` による skill-to-skill block は Cowork でも生存（§1.11 ベースで動く）

## 2.11 Bash tool 名は `mcp__workspace__bash`

CLI では Claude が `Bash` tool を呼ぶ。Cowork では **`mcp__workspace__bash`**（MCP server 経由）。hooks.json で matcher を `"Bash"` のみで書いていると **Cowork で frontmatter hook が発火しない**。

**実用上の対策**：
- 両環境対応の plugin にする場合、PreToolUse matcher を `"Bash"` と `"mcp__workspace__bash"` の両方で定義する
- もしくは `".*"` で全 tool を捕まえる

## 2.12 並列発火（§1.10 の Cowork 版）

Cowork でも plugin-level の SessionStart 配列は並列発火する。CLI と同じく書込先ファイルの排他制御は必要。ただし Cowork では §2.8 の通り file write 自体が Bash tool から見えないので、競合の影響は限定的。

## 2.13 二層 trust モデルの拡張（§1.12 の Cowork 版）

Cowork の architecture を踏まえると、信頼境界はさらに複雑になる：

| 役割 | 実行場所 | 信頼境界 |
|---|---|---|
| skill body | cloud VM (sandbox) | sandbox 内に閉じ込められる |
| plugin-level hook | **ホスト machine** | **ホストへの完全アクセスを持つ**（!!） |
| Bash tool | cloud VM (sandbox) | sandbox 内 |

つまり **plugin-level hook は Cowork の「sandbox」の外側で実行される**。ユーザの local machine 全体に対して権限を持つ。Plugin を install する時の信頼判断はここに集約される。

**実用上の含意**：
- Cowork は「安全な sandboxed env」というイメージで使われがちだが、**plugin の hook script は host を完全に触れる**
- Plugin 作者は hook script の内容を慎重にレビューする責任が重い
- 配布元の plugin を install する際は、hook 部分のコードを必ず読む文化を作る

## 2.14 cross-chat 隔離（§1.x には無い Cowork 固有）

Cowork は per-user で 1 つの VM を長期共有しており、chat ごとに Linux user account を切って隔離している。

- **データ隔離は POSIX file permission で実装** — 他 chat の `/sessions/<other-codename>/` には `cd` も `cat` もできない（Permission denied）
- **メタデータは漏れている** — `ls /sessions/` は world-readable なので、過去の全 chat の codename 一覧（CLI session 含む）は任意の plugin から enumerate 可能

**実用上の含意**：
- Plugin で「他の chat の存在を知る」「過去の chat 数を数える」等は実装可能（メタデータレベル）
- ただしファイル中身は読めないので、データ漏洩の経路にはなりにくい
- 「Cowork = 完全な per-chat VM」という素朴な前提は誤り

## 2.15 接続フォルダ (`request_cowork_directory`) と rm guard

Cowork は default では `outputs/` 以外への書込ができない（plugin dir も `uploads/` も read-only）。`request_cowork_directory` MCP tool を使うと、ユーザに承認 UI を出して任意のホストフォルダを RW で mount できる。

ただし **接続フォルダでも `rm` は blocked**：

```bash
rm /sessions/<codename>/mnt/Documents/foo.txt
# → rm: cannot remove ...: Operation not permitted
```

FUSE layer または上位の Cowork guard が delete を block している。**RW = create-new + modify は可、delete は不可**という制限付き許可。

**実用上の含意**：
- Plugin がユーザのホストファイルを誤って削除する事故は Cowork のレイヤで防がれる
- 「ファイルを一度書いて、後で消す」設計（一時ファイル等）は Cowork で動かない。書きっぱなしを前提に設計する

## 2.16 Cowork validator は CLI より圧倒的に厳しい

CLI の `claude plugin validate` で warning のみで通る違反項目を、Cowork は upload 時に hard reject する。今回の bisect で判明した reject 対象：

1. **plugin name の kebab-case 違反**（CLI ⚠ warning / Cowork ❌ hard reject）
2. **hook command 内の `${VAR^^}` 等 bash-specific parameter expansion**
3. **YAML single-quoted string の closing quote 漏れ**
4. **skill `description:` field 内の `${CLAUDE_*}` substitution markers や `<...>` angle brackets**
5. **`UserPromptExpansion` event entry**（CLI は通すが Cowork は reject）
6. **skill body / frontmatter command content の累積 threshold**（具体閾値未特定）

Cowork rejection は generic `Plugin validation failed` のみで理由表示が無い。CLI からは検知できない。

**実用上の対策**：
- 配布前に **Cowork 実機 upload テスト**を必ず通す
- CI で `claude plugin validate` の warning も failure 扱いする
- description field では `${...}` や `<...>` のような構文を**避け、bare token で書く**（例：`/sessions/<codename>/mnt/` ではなく `/sessions/CODENAME/mnt/`）

---

# 付録：CLI / Cowork 両対応の plugin を書く際のチェックリスト

| チェック項目 | 確認内容 |
|---|---|
| plugin name | 完全に kebab-case（小文字 + 数字 + ハイフンのみ） |
| YAML frontmatter | 全 single-quoted string の closing quote 確認 |
| hook command | bash-specific syntax (`${VAR^^}` 等) は使わない、または `bash -c` で wrap |
| hook command path 参照 | top-level echo は literal なので、`bash -c "..."` で wrap して `${CLAUDE_PLUGIN_ROOT}` 等を使う |
| PreToolUse matcher | `"Bash"` だけでなく `"mcp__workspace__bash"` も追加 |
| skill body の path 参照 | `${CLAUDE_PLUGIN_ROOT}` を使うなら、Cowork では Windows path に展開されることを前提に `find /sessions` 経路で localize できるように書く |
| skill description | `${CLAUDE_*}` や `<...>` を避ける |
| state 永続化 | Cowork では `${CLAUDE_PLUGIN_DATA}` の write は届かない、`/tmp` も不可。stdout → additionalContext 経路のみ |
| `PreToolUse:Bash` block | Cowork では plugin-level の block は無効。skill frontmatter で代替するか諦める |
| `UserPromptExpansion` event | Cowork validator が reject するので、Cowork 配布版では hooks.json から除外 |
| 削除操作 | 接続フォルダでも `rm` は不可。一時ファイルは作らない |
| userConfig | Cowork では UI が無い。CLI のみで使う設定として割り切る |
| 実機テスト | CLI で `claude plugin validate` PASS + Cowork で zip upload PASS + 実機 invoke で挙動確認、の 3 段 |

---

# 参考文献

- 検証結果の生データ：`findings/v2.1.146/observations.md`（1300 行超）
- 集計レポート：`findings/v2.1.146/report.md`
- 元になった研究記録（v2.1.118-119 時点）：`/home/kazukinagata/projects/sandbox/research.md`
- 検証プラグイン本体：`verifier/`
- Cowork 専用検証 zip：`findings/v2.1.148/verifier-cowork-*.zip`
