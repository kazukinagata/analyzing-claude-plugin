# Claude Code Plugin 作成ガイド — CLI と Cowork の挙動差分まとめ

## この文書の目的

Claude Code（Anthropic 公式 CLI / Claude Desktop アプリ）には plugin 機構があり、プロジェクト固有の skill（指示書）や hook（バックグラウンド処理）を定義できる。ところが公式 docs には書かれていない仕様や、ドキュメントと挙動が矛盾する箇所が多数あり、plugin を実装すると「動くはずなのに動かない」「CLI では動くのに Cowork（Claude Desktop の VM 実行モード）では動かない」といった事象に頻繁にぶつかる。

本資料は、それらの落とし穴を実機検証で洗い出した結果をチーム共有用にまとめたもの。検証対象は **Claude Code v2.1.146（CLI 側）+ v2.1.146-148（Cowork 側）**、2026 年 5 月時点。

> ## ⚠ 検証環境の前提（必読）
>
> **本資料の Cowork 検証は「Windows ホスト + WSL2 Ubuntu がインストール済み」の 1 台に特化している。**
> - **CLI 側**：WSL2 上の Ubuntu で `claude` を実行
> - **Cowork 側**：その Windows ホストの **Claude Desktop アプリ（GUI）** を利用（WSL 内にインストールした Cowork ではない）
>
> 第 2 章で「hook が WSL2 で実行される」「PATH に `/usr/lib/wsl/lib` が入る」「`HOME=/home/<user>`」等と書いているのは、**このマシン構成に依存する具体値**であって Cowork 普遍の性質ではない。理由は §2.0 の通り「Windows 上の Claude が hook の POSIX シェルコマンドを実行する際、ホスト側で利用可能な WSL2 に委譲したから」と推定され、**Cowork が WSL VM である／WSL に依存しているという意味ではない**。
>
> | | このマシン固有（一般化不可） | ホスト OS に依らず成立（一般化可） |
> |---|---|---|
> | | `/usr/lib/wsl/lib`・`/mnt/c` を含む PATH、`hostname=Windows名`、`HOME=/home/<user>`、hook が WSL2 で動く事実 | hook は **Cowork VM の外＝ホスト側**で動く / hook の env は strip される / hook の FS と VM の FS は別 namespace / hook はそのホスト環境のフル権限を持つ |
>
> **WSL 無しの Windows / macOS は未検証**。それらでは hook の実行場所・パス・hostname は変わる（が、上表「一般化可」の原則は成り立つと考えられる）。

- **第 0 章** — Plugin の物理構成と 3 種類のコード実行場所
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
| **Cowork** | Claude Desktop アプリ（Windows）で動く VM 実行モード。本資料の検証で **実体は host-adjacent な VM + virtio-fs**（つまり「クラウド」ではなくユーザ機の隣接 VM）であることが判明している。なお plugin-level hook は **この VM の中ではなくホスト側**で実行される（本検証機では WSL2 Ubuntu。§2.0） |

---

# 第 0 章：Plugin の物理構成と 3 種類のコード実行場所

第 1 章以降で繰り返し出てくる「plugin-level hook」「skill frontmatter hook」「Bash tool subprocess」が **それぞれ別ファイル・別プロセスで実行される** ことを先に把握しておくと話が早い。

## ディレクトリ構造

最小限の plugin はこんな構造：

```
my-plugin/                              ← plugin root
├── .claude-plugin/
│   └── plugin.json                     ← plugin の metadata + userConfig 宣言
├── hooks/
│   ├── hooks.json                      ← ① plugin-level hook の定義
│   └── greet.sh                        ← hook が呼ぶシェルスクリプト本体
└── skills/
    └── hello-world/
        └── SKILL.md                    ← ② skill frontmatter hook 定義
                                          + skill 本文（指示書）
                                          + 本文中のコードブロック = ③ Bash tool で実行
```

## 3 種類のコード実行場所と、それぞれの定義方法

### ① Plugin-level hook（`hooks/hooks.json` に定義）

plugin 全体で動く常駐 hook。`SessionStart` `UserPromptSubmit` `PreToolUse` 等のイベントに紐付ける。

**`hooks/hooks.json` の例：**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/greet.sh\"" }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "echo 'plugin-level: about to run a Bash tool call'" }
        ]
      }
    ]
  }
}
```

**`hooks/greet.sh` の中身：**

```sh
#!/bin/sh
echo "[greet] hello from plugin-level hook, plugin root=$CLAUDE_PLUGIN_ROOT"
```

ポイント：
- `${CLAUDE_PLUGIN_ROOT}` は Claude Code 本体が **command を実行する直前に文字列置換**する（事前置換）
- 起動シェルは `/bin/sh`（WSL/Ubuntu では dash）。bash 固有の構文を書くと死ぬ（後述 §1.3）
- `matcher` の正規表現で対象 tool / event subtype を絞れる

### ② Skill frontmatter hook（`skills/<name>/SKILL.md` の YAML frontmatter に定義）

特定 skill が invoke された後に有効化される hook。skill ローカルな処理に向く。

**`skills/hello-world/SKILL.md` の例：**

```markdown
---
name: hello-world
description: "A trivial hello-world skill that demonstrates the three execution tiers."
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'echo "[fm-hook] frontmatter hook fired before Bash tool"'
---

# hello-world

このスキルは「3 種類のコード実行場所」を体感するためのもの。下の bash を実行してください：

​```bash
echo "[body] this runs in the Bash tool subprocess"
echo "PWD=$PWD"
echo "CLAUDE_PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT:-(unset)}"
​```
```

ポイント：
- 上半分の `---` で囲まれた YAML が frontmatter
- `hooks:` ブロックに書いた command は **この skill が一度 invoke された後**に登録される（後述 §1.8 — 重要な落とし穴）
- `user-invocable: true` を付けると `/<plugin-name>:hello-world` で slash 起動可能になる（plugin 名 + ":" + skill 名）

### ③ Bash tool subprocess（SKILL.md 本文中のコードブロック、または Claude が自発的に書く bash）

Claude（LLM）が `Bash` tool を呼び出すと起動するシェルプロセス。**ユーザに ON/OFF を確認した上で実行される**（permission UI が出る）。skill body の ` ```bash ` ブロックは「Claude にこの bash を実行するよう促す」という意味で、結局 Bash tool 経由で動く。

skill body 内の bash が実行されるまでの流れ：

```
ユーザ「/my-plugin:hello-world を起動して」
  ↓
Claude Code: skill 起動を decide
  ↓
PreToolUse hook (上記 ①②) が発火 ※ ① はずっと有効、② は今回が初回 invoke なのでこれ以降有効化
  ↓
Skill body markdown を Claude に context として load（このとき ${VAR} 置換が走る）
  ↓
Claude が body 中の ```bash``` を読んで「これを実行しよう」と判断
  ↓
Bash tool 起動 → ユーザに permission 確認 → /bin/sh で実行 (= ③ Bash tool subprocess)
  ↓
PreToolUse hook (Bash matcher) が再度発火
  ↓
出力を Claude が読む
```

3 種類のコードがそれぞれ **別プロセス・別 env var set** で動く点がこの後の全章の前提になる。

---

# 第 1 章：CLI で plugin を作るときに知っておくべき知識

## 1.1 環境変数の伝播は 3 階層で非対称

§0 で示した 3 種類のプロセスは、Claude Code 本体から渡される env var の集合が違う。これを知らずに「plugin-level hook では使えた変数が、skill 内 bash では空になる」ような事故が起きる。

### 伝播マトリクス（CLI 観測）

| 環境変数 | ① plugin-level hook | ② skill frontmatter hook | ③ Bash tool subprocess |
|---|:---:|:---:|:---:|
| `CLAUDE_PLUGIN_ROOT` | ✅ | ✅ | ❌ |
| `CLAUDE_PLUGIN_DATA` | ✅ | ❌ | ❌ |
| `CLAUDE_PROJECT_DIR` | ✅ | ✅ | ❌ |
| `CLAUDE_PLUGIN_OPTION_<KEY>` | ✅（機密値含む） | ❌ | ❌ |
| `CLAUDE_CODE_ENTRYPOINT` 等 `CLAUDE_CODE_*` | ✅ | ✅ | ✅ |

実装ソースの根拠は `src/utils/hooks.ts` の `if (pluginId)` ガードと `SkillHookMatcher` 型に pluginId が無い、という構造。意図的設計。

### 実装例

env 伝播を観測する skill。同じ env var 名を 3 経路から dump して比較する：

**`hooks/hooks.json`**（① plugin-level hook 側）：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command",
            "command": "echo \"[plugin-level] ROOT=[$CLAUDE_PLUGIN_ROOT] DATA=[$CLAUDE_PLUGIN_DATA] OPT_API=[$CLAUDE_PLUGIN_OPTION_API_SECRET]\"" }
        ]
      }
    ]
  }
}
```

**`skills/env-probe/SKILL.md`**（② skill frontmatter hook + ③ Bash tool subprocess）：

```markdown
---
name: env-probe
description: "Compare env vars across 3 execution tiers"
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'echo "[frontmatter] ROOT=[$CLAUDE_PLUGIN_ROOT] DATA=[$CLAUDE_PLUGIN_DATA] OPT_API=[$CLAUDE_PLUGIN_OPTION_API_SECRET]"'
---

# env-probe

次の bash を実行してください：

​```bash
echo "[body] ROOT=[${CLAUDE_PLUGIN_ROOT:-(unset)}] DATA=[${CLAUDE_PLUGIN_DATA:-(unset)}] OPT_API=[${CLAUDE_PLUGIN_OPTION_API_SECRET:-(unset)}]"
​```
```

これを起動すると、Claude の応答画面に 3 行出る：

```
[plugin-level]  ROOT=[/path/to/plugin]    DATA=[/home/user/.claude/plugins/data/my-plugin]  OPT_API=[secret-xyz]
[frontmatter]   ROOT=[/path/to/plugin]    DATA=[]                                            OPT_API=[]
[body]          ROOT=[(unset)]             DATA=[(unset)]                                     OPT_API=[(unset)]
```

→ frontmatter には DATA / OPT_* が来ない、body (Bash tool) には何も来ない、ということが目に見えて分かる。

### 実用上の含意

- Skill 内の bash から plugin install dir を参照したい場合は `${CLAUDE_PLUGIN_ROOT}` を **skill body の置換経由**で取得する（後述 §1.7）。env var には期待しない
- ユーザ設定値を hook に渡したいなら **plugin-level hook で扱う**。skill frontmatter hook には値が来ない
- 機密値（`sensitive: true` の userConfig）は plugin-level hook env にだけ来るので、機密処理は plugin-level に閉じ込める

## 1.2 `${VAR}` の事前置換は文脈ごとに効く範囲が違う

Claude Code 本体は hook command や skill body の文字列を実行前に `${VAR}` 形式でスキャンして置換する（**Claude Code 事前置換**）。一方、シェル展開（`$VAR`）は実行時に OS シェルが行う。両者が混在して非対称な挙動になる。

### 置換可否マトリクス

| 記法 | plugin-level hook command | skill frontmatter hook command | skill body markdown |
|---|:---:|:---:|:---:|
| `${CLAUDE_PLUGIN_ROOT}` | ✅ | ✅ | ✅ |
| `${CLAUDE_PLUGIN_DATA}` | ✅ | ❌ **validator block** | ✅ |
| `${user_config.KEY}` | ✅ 非機密値は実値（unset 時は hook entry が silent skip）／機密値は plain 平文で実値 | ❌ literal で `/bin/sh` に渡る → `Bad substitution` エラー | ✅ 非機密値は実値（unset 時は literal）／❌ 機密値は `[sensitive option 'KEY' not available in skill content]` という block 文字列に置換される |
| `${CLAUDE_SKILL_DIR}` | ❌ literal | ❌ literal | ✅（SKILL.md の dirname） |
| `${CLAUDE_SESSION_ID}` | ❌ literal | ❌ literal | ✅（session UUID） |
| `${CLAUDE_PROJECT_DIR}` | ✅ | ❌ literal | ✅ |

検証根拠：probe 22 (`verifier/skills/22-substitution-frontmatter/`)。single-quote isolation で shell expansion を抑止し、Claude Code 事前置換のみを観測したもの。生 log は `findings/v2.1.150/probe-22/subst.log`。

### tier 別 allowlist のまとめ

事前置換は **tier ごとに別 allowlist** で運用されている。狭い順：

| tier | 置換される var |
|---|---|
| **skill frontmatter hook** | `PLUGIN_ROOT` のみ |
| **plugin-level hook** | `PLUGIN_ROOT`, `PLUGIN_DATA`, `PROJECT_DIR`, `user_config.KEY` |
| **skill body markdown** | `PLUGIN_ROOT`, `PLUGIN_DATA`, `SKILL_DIR`, `SESSION_ID`, `PROJECT_DIR`, `user_config.KEY` |

実用上の含意：
- 「全 tier で動く plugin」を作るときの最大公約数は `${CLAUDE_PLUGIN_ROOT}` のみ
- session ID や skill dir を hook 側に渡したい場合は、`${CLAUDE_PLUGIN_ROOT}/hooks/script.sh` 経由で wrapper script を起動し、その中で env var 経由で `$CLAUDE_SESSION_ID` 等を読む（env propagation は §1.1 マトリクス通り）

### 重要：hook command 列の「✅」は事前置換ではなくシェル展開（2026-05-27, `cowork-presub-probe` で判明）

上の「置換可否マトリクス」は「`${VAR}` が実値に解決されるか」を測ったものだが、**hook command tier（plugin-level / frontmatter）の `${CLAUDE_PLUGIN_*}` の ✅ は、Claude Code 事前置換ではなく `/bin/sh` のシェル展開（env 経由）だった**。両者は別物：

| 経路 | 仕組み | quote 感度 |
|---|---|---|
| Claude Code 事前置換 | command 文字列を shell 前に書き換え | **quote 非依存**（single-quote 内でも置換、probe 22 で確認） |
| シェル展開 | `/bin/sh` が実行時に env から `$VAR` 展開 | **quote 依存**（single-quote で抑止） |

`cowork-presub-probe` で single-quote isolation すると：

- `echo '${CLAUDE_PLUGIN_ROOT}'`（single-quote）→ **CLI でも literal `${CLAUDE_PLUGIN_ROOT}`**。pre-sub が quote 非依存なら single-quote 内でも実値になるはずなので、これは pre-sub ではなく **shell 展開**である証拠。
- 一方 probe 22 では `'${user_config.hello_message}'`（single-quote）が値に解決されていた。`user_config` は env 変数を持たないので、これは **pre-sub 以外あり得ない**（pre-sub は quote 非依存）。

つまり tier ごとの「真の事前置換 allowlist」と「env シェル展開で解決される var」を分けると：

| tier | 真の事前置換（quote 非依存） | env シェル展開で解決（quote 依存） |
|---|---|---|
| plugin-level hook | `${user_config.KEY}` のみ | `${CLAUDE_PLUGIN_ROOT/DATA/PROJECT_DIR}`（env が §1.1 で set されているから） |
| skill frontmatter hook | **無し**（`fm-presub-probe` で確認） | `${CLAUDE_PLUGIN_ROOT/PROJECT_DIR}`（env set のもの。bare 解決 / single-quote literal で確定） |
| skill body | `PLUGIN_ROOT/PLUGIN_DATA/SKILL_DIR/SESSION_ID/PROJECT_DIR/user_config.KEY` 全部（env は空なのに解決＝quote 非依存の真の pre-sub、probe 22 で確認） | — |

> skill frontmatter hook の裏取り（2026-05-27, `fm-presub-probe/`）：frontmatter PreToolUse hook で `echo "ROOT_BARE=${CLAUDE_PLUGIN_ROOT}"` と `echo 'ROOT_SQ=${CLAUDE_PLUGIN_ROOT}'` を両方書いたところ、CLI では `ROOT_BARE=/実パス` / `ROOT_SQ=${CLAUDE_PLUGIN_ROOT}`（literal）、`PROJ_BARE=/実パス` / `PROJ_SQ=${CLAUDE_PROJECT_DIR}`（literal）。bare だけ解決し single-quote が literal = シェル展開であって pre-sub ではない、と確定。これで §1.1（env set）と §1.2 旧表記（pre-sub literal）の見かけの矛盾も解消した（別機構を測っていただけ）。なお frontmatter hook は Cowork では発火しないので（§2.9）、この検証は CLI 専用。

含意：**hook command 中の `${CLAUDE_PLUGIN_ROOT}` は「事前置換対象」ではなく「env シェル展開対象」**。だから §1.1 で env が来ない Cowork の plugin-level hook では解決できない（§2.1 / §2.2）。skill body だけが env 非依存の真の事前置換で、Cowork でも（Windows path だが）解決する（§2.7）。

skill frontmatter hook に `${CLAUDE_PLUGIN_DATA}` を書くと、install 時の validator が以下メッセージで reject する：

```
Hook command references ${CLAUDE_PLUGIN_DATA} but only ${CLAUDE_PLUGIN_ROOT}
is available for skill hooks (${CLAUDE_PLUGIN_DATA} is plugin-only).
```

`${CLAUDE_SKILL_DIR}` `${CLAUDE_SESSION_ID}` `${CLAUDE_PROJECT_DIR}` は validator 通過するが、ランタイムで literal `${...}` のまま `/bin/sh` に渡って single-quote 内なら無害、double-quote / 裸記述だと `/bin/sh` の Bad substitution エラーになる。

### userConfig の保存形式に関する注意

UI (`/plugin configure verifier@verifier-mp`) が書き込む `settings.json` の構造は v2.1.150 で以下のように **`options` 入れ子**：

```json
{
  "pluginConfigs": {
    "verifier@verifier-mp": {
      "options": {
        "hello_message": "hello-from-probe-22"
      }
    }
  }
}
```

研究 v2.1.119 では入れ子なし（`pluginConfigs.<id>.<key>` 直下）に書いていたが、UI が `options` を挟む形式に統一されている。手動で settings.json を書く場合はこの構造に合わせる。

### 実装例

**A. plugin-level hook で `${user_config.KEY}` を使う（OK 経路）：**

```json
// hooks/hooks.json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command",
            "command": "echo \"greeting: ${user_config.hello_message}\"" }
        ]
      }
    ]
  }
}
```

ユーザが `hello_message` に `"hello-from-cli"` を設定していれば、SessionStart 時に "greeting: hello-from-cli" が context に注入される。

**B. skill frontmatter hook で `${user_config.KEY}` を使う（NG 経路）：**

```markdown
---
name: bad-skill
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'echo "greeting: ${user_config.hello_message}"'
---
```

→ validator は通る。しかし実行時に `/bin/sh` が `${user_config.hello_message}` を変数名として解釈しようとし、不正なシンボルなので：

```
/bin/sh: 1: Bad substitution
```

で死ぬ。

**C. skill body の `${VAR}` 置換（OK 経路、ただし invoke 時のみ）：**

```markdown
# my-skill

次の bash を実行：

​```bash
echo "plugin install path: ${CLAUDE_PLUGIN_ROOT}"
echo "this skill dir: ${CLAUDE_SKILL_DIR}"
echo "session id: ${CLAUDE_SESSION_ID}"
echo "project dir: ${CLAUDE_PROJECT_DIR}"
​```
```

→ Claude が skill を invoke する時に Claude Code 本体が置換するので、Claude に渡る context は：

```
echo "plugin install path: /home/user/.claude/plugins/cache/<...>/my-plugin"
echo "this skill dir: /home/user/.claude/plugins/cache/<...>/my-plugin/skills/my-skill"
echo "session id: 9307ae27-a40f-44d8-85d9-32838abbd9a1"
echo "project dir: /home/user/my-project"
```

なお v2.1.119 までは skill body の `${CLAUDE_PROJECT_DIR}` だけが literal のまま残るという既知の制約があった。v2.1.146 で改善され、上記 4 つすべて置換されるようになった。

### 実用上の対策

- skill frontmatter で userConfig を参照しない（`Bad substitution` で死ぬ）
- 置換可否を testing するには「dummy skill を作って各経路で `echo ${変数名}` させて context に出るか目視」が最も確実

## 1.3 hook の実行シェルは `/bin/sh`（WSL/Ubuntu では dash）

bash 想定で hook を書くと事故る。

### 具体例

| 書いた構文 | 何が起きるか |
|---|---|
| `[[ "$X" = "y" ]] && echo ok` | `/bin/sh: 1: [[: not found` |
| `${PWD^^}`（大文字化） | `Bad substitution` |
| `read -a array` | `read: bad option: -a` |
| `$RANDOM` | dash では空文字列に展開 |
| `arr=(a b c); echo ${arr[0]}` | `Syntax error: "(" unexpected` |

### 実装例

**NG パターン**（CLI でも実行時にエラー）：

```json
// hooks/hooks.json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command",
            "command": "if [[ -d \"$CLAUDE_PROJECT_DIR\" ]]; then echo found; fi" }
        ]
      }
    ]
  }
}
```

→ 実行時に `/bin/sh: 1: [[: not found` が stderr に出て、hook は何もしない。

**OK パターン**（bash 機能を使いたいなら `bash -c` で wrap）：

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command",
            "command": "bash -c 'if [[ -d \"$CLAUDE_PROJECT_DIR\" ]]; then echo found; fi'" }
        ]
      }
    ]
  }
}
```

**もしくは POSIX sh の範囲で書く**：

```json
{
  "command": "if [ -d \"$CLAUDE_PROJECT_DIR\" ]; then echo found; fi"
}
```

### 確認方法

WSL Ubuntu で `/bin/sh` の実体を確認：

```bash
$ ls -l /bin/sh
lrwxrwxrwx 1 root root 4 ... /bin/sh -> dash

$ /bin/sh -c 'echo $BASH_VERSION'
（空行 — BASH_VERSION は bash 固有なので dash では空）
```

## 1.4 `sensitive: true` は保存先を分けるだけ、ランタイムは平文で env に出る

userConfig で `sensitive: true` フラグを付けると、設定値は `~/.claude/settings.json` ではなく OS keychain や `~/.claude/.credentials.json` に保存される。**ところがランタイムでは `CLAUDE_PLUGIN_OPTION_<KEY>` env var に平文で plugin-level hook に渡る**。

### 実装例

**`.claude-plugin/plugin.json`：**

```json
{
  "name": "my-plugin",
  "version": "0.1.0",
  "userConfig": {
    "hello_message": {
      "type": "string",
      "title": "Hello message",
      "description": "Non-sensitive probe value (stored in settings.json)"
    },
    "api_secret": {
      "type": "string",
      "title": "API secret",
      "description": "Stored separately in OS keychain or .credentials.json",
      "sensitive": true
    }
  }
}
```

ユーザが `api_secret=secret-xyz` を設定したとき：

**保存先：**
- `hello_message` → `~/.claude/settings.json` に平文
- `api_secret` → `~/.claude/.credentials.json` の `pluginSecrets` セクション（または OS keychain）

**ランタイム挙動（plugin-level hook env）：**

```bash
# hooks/hooks.json で何かが呼ばれた瞬間
$ env | grep ^CLAUDE_PLUGIN_OPTION_
CLAUDE_PLUGIN_OPTION_HELLO_MESSAGE=hello-from-cli
CLAUDE_PLUGIN_OPTION_API_SECRET=secret-xyz                ← 平文で渡る！
```

つまり `sensitive: true` は **「他のユーザや他 plugin が settings.json を覗いたときに見られないようにする」だけ**で、自分の plugin の hook 内ではフルアクセス可能。

### 実装ソースのコメント

`src/utils/hooks.ts` 近辺：

> hooks run the user's own code, same trust boundary as reading keychain directly

つまり「hook を作る人は keychain を読むのと同じ信頼境界」と明示。

### ただし skill body には `sensitive: true` 値は届かない（Claude Code 本体が block）

§1.2 マトリクスの通り、`${user_config.<KEY>}` を skill body に書いた場合：

- 非機密 key → 値が平文で置換される（v2.1.150 で probe 22 確認）
- `sensitive: true` 付き key → **`[sensitive option 'KEY' not available in skill content]` という block 文字列**に置換される（v2.1.150 で probe 22 確認、binary strings にも literal が存在）

つまり Claude Code 本体側で「skill body 経由で機密値が Claude の context / transcript に漏れる」経路を明示的に封じる設計になっている。

```bash
# SKILL.md 本文に書いたコード
echo "secret=${user_config.api_secret}"
```

→ 実行時の Bash tool に渡る文字列：

```bash
echo "secret=[sensitive option 'api_secret' not available in skill content]"
```

→ Claude の context にもこの literal 文字列が出るので、機密値は漏れない代わりに **skill のコードが意図通り動かなくなる**。`sensitive: true` key を skill body に書く設計自体が誤り、と読み取れる挙動。

### 実用上の対策

- 機密値を扱う処理は **plugin-level hook の範囲に閉じ込める**（skill body は Claude Code 本体が block、skill frontmatter は env が伝わらない）
- ログに env をダンプする処理を入れる場合、`CLAUDE_PLUGIN_OPTION_*` を必ずマスクする：

```sh
env | grep '^CLAUDE_' | sed 's/\(SECRET\|TOKEN\|KEY\)=.*$/\1=[REDACTED]/'
```

## 1.5 userConfig 入力 UI の trigger ルールが複雑

「`/plugins` UI から enable した時に入力フォームが出ない」「`disable → enable` でも prompt が出ない」といった事象がよく報告される（GitHub issues #39455 / #39827 で "dead config" と呼ばれている）。

### Trigger 表

| 操作 | prompt 表示 |
|---|---|
| `claude plugin install` / `enable`（CLI シェル） | ❌ silent |
| `/plugins` UI → Configure options（手動） | ✅ |
| `/plugins` UI → disable → enable | プラグインのどこかで `${user_config.KEY}` が参照されており、かつ値が未設定の場合のみ ✅ |
| 参照あり + 未設定で hook が走った場合 | hook error `Plugin option "X" isn't set.` |

### 実装例

**「参照なし」状態（dead config）の例：**

```json
// plugin.json
{
  "userConfig": {
    "my_unused_key": { "type": "string" }
  }
}
```

```json
// hooks/hooks.json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [
        { "type": "command", "command": "echo hello" }   ← my_unused_key を参照していない
      ]}
    ]
  }
}
```

→ `claude plugin install` しても、`/plugins` で disable→enable しても、UI は出ない。**永久に未設定**。

**「参照あり」状態（trigger 有効）の例：**

```json
// hooks/hooks.json
{
  "hooks": {
    "SessionStart": [
      { "hooks": [
        { "type": "command", "command": "echo greeting=${user_config.my_required_key}" }
      ]}
    ]
  }
}
```

→ `/plugins` で disable→enable すると prompt UI が出る（参照あり + 未設定なので）。

**ユーザの手動 fallback 経路（README に書いておくべき）：**

```bash
# CLAUDE_CONFIG_DIR が設定されていればそちら、未設定なら ~/.claude/
$ vi ~/.claude/settings.json
```

```json
{
  "pluginConfigs": {
    "my-plugin@my-marketplace": {
      "my_required_key": "value-set-manually"
    }
  }
}
```

→ これで `${user_config.my_required_key}` が実値で置換されるようになる。

### 実用上の対策

- 単に「`/plugins` で入力 UI が出る」と信じて任せると、参照されていない userConfig は **永久に未設定のまま**になる
- README で「初回 install 後は `settings.json` を直接編集してください」と明示する
- または skill body で値の有無をチェックして、未設定なら Claude にユーザに値を聞かせる

## 1.6 marketplace cache と実行パスは別物

公式 docs は「marketplace plugin は `~/.claude/plugins/cache/` にコピーされて、そこから実行される」と書いているが、**ローカル marketplace の場合 `CLAUDE_PLUGIN_ROOT` は source ディレクトリを指す**。

### 実装例

開発フロー：

```bash
$ ls /path/to/my-plugin/
.claude-plugin/  hooks/  skills/

# ローカル dir を marketplace 登録
$ claude plugin marketplace add /path/to/my-plugin

# install
$ claude plugin install my-plugin@my-marketplace
```

install 後の状態：

```bash
$ cat ~/.claude/plugins/installed_plugins.json | jq '.["my-plugin@my-marketplace"]'
# → settings 各種

$ ls ~/.claude/plugins/cache/<hash>/
.claude-plugin/  hooks/  skills/    ← コピー先（docs に書かれている経路）
```

claude を起動して skill 内で確認：

```bash
$ /verifier:01-env-propagation
# hook が echo した結果
CLAUDE_PLUGIN_ROOT=/path/to/my-plugin    ← cache ではなく source dir！
```

つまり `~/.claude/plugins/cache/` にコピーは存在するが、hook は **source dir を直接読んで実行**する。

### 実用上の含意

- 開発中の plugin を編集すると即座に反映される（cache クリア不要）
- 「`/path/to/my-plugin/` を mv / rm したら plugin が壊れる」逆に言うとそれだけ source dir に依存している
- 配布されたユーザ環境では git の URL ベースで install されるので、cache が実行パスになる場合もある（その時は別挙動）。検証は config の中身を確認するのが確実

## 1.7 skill body の `${VAR}` 置換は invoke 時のみ

SKILL.md の本文に書いた `${CLAUDE_PLUGIN_ROOT}` 等は、**skill が invoke されて Claude の context に load される瞬間**に Claude Code 本体が置換する。一方、ユーザや別の Claude が Read / Grep ツールで SKILL.md を**ファイルとして読んだ場合は literal のまま**。

### 実装例

**`skills/double-faced/SKILL.md`：**

```markdown
---
name: double-faced
user-invocable: true
---

# double-faced

Check the value of `${CLAUDE_PLUGIN_ROOT}` here.

​```bash
echo "PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT}"
​```
```

**経路 A: Read tool で SKILL.md を読む（別 Claude が経路として使う）：**

```
User: "double-faced スキルの SKILL.md の中身を見せて"
Claude: [Read tool で /path/to/.../double-faced/SKILL.md を読む]
Claude の応答に出る文字列：
  Check the value of ${CLAUDE_PLUGIN_ROOT} here.
  echo "PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT}"
                  ↑ literal のまま
```

**経路 B: skill を invoke する：**

```
User: "/my-plugin:double-faced を起動して"
Claude Code: SKILL.md を context に load (ここで置換が走る)
Claude が受け取る context：
  Check the value of /home/user/.claude/plugins/cache/<hash>/skills/double-faced here.
                    ↑ 実値
  echo "PLUGIN_ROOT=/home/user/.claude/plugins/cache/<hash>/skills/double-faced"
                   ↑ 実値
Claude が ```bash``` を実行：
  PLUGIN_ROOT=/home/user/.claude/plugins/cache/<hash>/skills/double-faced
```

### 実用上の含意

- Skill 内 bash で `${CLAUDE_PLUGIN_ROOT}` を使うのは OK（invoke 経路）
- 別 skill の SKILL.md を Read tool で読ませて中身を引用する設計は **literal が見えて混乱**する。注意書きを入れるか、別ファイルで実値表を提供する
- 「skill body に書いた絶対パスを文字列としても、実行値としても両方使う」みたいな設計は両用しにくい

## 1.8 skill frontmatter hook は「一度 invoke した後」に登録される

これは強烈な落とし穴。skill frontmatter hook は、その skill が一度起動された後に有効化される。

### 実装例：SessionStart once:true が不発する例

**`skills/init-once/SKILL.md`：**

```markdown
---
name: init-once
user-invocable: true
hooks:
  SessionStart:
    - matcher: "startup"
      hooks:
        - type: command
          command: 'echo "[init-once] SessionStart fired"'
          once: true
---

# init-once

This skill should set up something on the first session start.
```

期待：claude を起動した時に `[init-once] SessionStart fired` が出る。

実際：
- claude 起動 → SessionStart event 発火
- skill `init-once` はまだ invoke されていないので、その frontmatter hook **未登録**
- SessionStart event は plugin-level hook には届くが、`init-once` の frontmatter hook はスキップ
- ユーザが `/my-plugin:init-once` を invoke すると、ここで初めて frontmatter hook が登録される
- でも SessionStart はもう発火し終わっている → **永久に出ない**

### 実装例：自スキルの起動を block しようとして失敗する例

**`skills/self-block/SKILL.md`：**

```markdown
---
name: self-block
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Skill"
      hooks:
        - type: command
          command: 'echo "{\"decision\":\"block\",\"reason\":\"self-block tried\"}"'
---

# self-block

This skill tries to block itself from running.
```

期待：ユーザが `/my-plugin:self-block` を呼ぶと、自分の frontmatter hook が PreToolUse:Skill で自身を block する。

実際：
- ユーザが `/my-plugin:self-block` を invoke
- skill が load される
- load 後に frontmatter hook が登録される（**先に skill が動いてから登録**）
- 自分は block されず無事 invoke 完了
- 後続の tool 呼び出しは block 対象になる

### 実装例：「いったん起動すれば後続を block」する正しい使い方

CLI で「特定の bash コマンドを block」を実現したいなら：

**`skills/bash-guard/SKILL.md`：**

```markdown
---
name: bash-guard
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: 'tool_input=$(cat); if echo "$tool_input" | grep -q "rm -rf /"; then echo "{\"decision\":\"block\",\"reason\":\"prevented rm -rf /\"}"; else cat <<< "$tool_input"; fi'
---

# bash-guard

Activates a Bash guard for the rest of this claude session. Run me first.

​```bash
echo "bash-guard armed"
​```
```

期待運用：ユーザが claude を起動したら、最初に必ず `/my-plugin:bash-guard` を invoke する。これで以降の Bash tool 呼び出しに対して PreToolUse hook が動いて `rm -rf /` を block する。

### 実用上の対策

- 「skill 起動時の準備処理」は **plugin-level hook** に書く。skill frontmatter には書かない
- 「特定の他 skill を block」したい場合は、自分が一度 invoke される必要がある。ユーザに「先にこの skill を起動してください」と促すフローが必須
- README で「起動順」を明示

## 1.9 slash 起動と自然言語起動で発火する hook が違う

ユーザが skill を起動する経路は 2 つあり、それぞれ Claude Code 内部の挙動が違う。

| 観測項目 | 自然言語経由（"○○ skill を起動して"） | slash 経由（`/<plugin>:<skill>`） |
|---|:---:|:---:|
| `Skill` tool が呼ばれる | ✅ | ❌ |
| `PreToolUse:Skill` 発火 | ✅ | ❌ |
| `UserPromptSubmit` 発火 | ✅ | ✅ |
| `UserPromptExpansion` 発火（CLI のみ） | ❌ | ✅ |

### 実装例：どの hook が発火するかを観測する

**`hooks/hooks.json`：**

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [
        { "type": "command", "command": "echo '[tag=user-prompt-submit]'" }
      ]}
    ],
    "UserPromptExpansion": [
      { "hooks": [
        { "type": "command", "command": "echo '[tag=user-prompt-expansion]'" }
      ]}
    ],
    "PreToolUse": [
      { "matcher": "Skill",
        "hooks": [
          { "type": "command", "command": "echo '[tag=pretool-skill]'" }
      ]},
      { "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "echo '[tag=pretool-bash]'" }
      ]}
    ]
  }
}
```

**実験 A — slash 起動：**

```
User: /my-plugin:foo
Hook 発火順（log を見ると）：
  [tag=user-prompt-submit]
  [tag=user-prompt-expansion]
  [tag=pretool-bash]              ← skill 本文の bash 実行時
                                  ← [tag=pretool-skill] は出ない
```

**実験 B — 自然言語起動：**

```
User: foo skill を起動してください
Hook 発火順：
  [tag=user-prompt-submit]
                                  ← [tag=user-prompt-expansion] は出ない
  [tag=pretool-skill]              ← Skill tool 経由
  [tag=pretool-bash]
```

### 実用上の対策

- 起動経路に依存しない検知が欲しいなら、`UserPromptSubmit` で prompt 文字列を見る or 両経路の hook を組み合わせる
- 「skill が起動したら必ず ○○ を実行」を担保したい場合、skill body 内の bash 冒頭に書くのが最も確実

## 1.10 同じ hook 配列内のエントリは並列で走る

hooks.json 内で同じイベントに対して複数の command を array で並べた場合、それらは **並列に起動される**（配列順に逐次ではない）。観測すると、array order と log 書き込み順が逆転する。

### 実装例

**`hooks/hooks.json`：**

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/parallel-a.sh\"" },
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/parallel-b.sh\"" },
          { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/parallel-c.sh\"" }
        ]
      }
    ]
  }
}
```

**`hooks/parallel-a.sh`：**

```sh
#!/bin/sh
sleep 0.2
ns=$(date +%s%N)
flock -x "$CLAUDE_PROJECT_DIR/parallel.log.lock" sh -c "
  echo '[parallel-a end_ns=$ns pid=$$]' >> '$CLAUDE_PROJECT_DIR/parallel.log'
"
```

`parallel-b.sh` は sleep 0.4、`parallel-c.sh` は sleep 0.0、それぞれ似た形。

claude 起動後、`parallel.log` を見ると：

```
[parallel-c end_ns=1747896012345678901 pid=12345]      ← sleep 0 なので最初
[parallel-a end_ns=1747896012545678902 pid=12346]      ← sleep 0.2
[parallel-b end_ns=1747896012745678903 pid=12347]      ← sleep 0.4
```

→ array 順 (a, b, c) ではなく、sleep 短い順 (c, a, b)。**3 つの hook が同時に起動されている**証拠。

### 実用上の対策

- 同じファイルに書き込む処理を並列で複数走らせると race condition が起きる。`flock` で排他制御するか、書込先ファイルを分ける
- 「hook A の出力を hook B が読む」前提の設計はダメ。順序保証なし
- 1 配列に並べる代わりに、ロジックを 1 スクリプトに統合して逐次実行にする手もある

## 1.11 skill 間 block は frontmatter `PreToolUse:Skill` で可能

ある skill が起動された時に別の skill を起動しようとするのを block できる。

### 実装例

**`skills/blocker/SKILL.md`：**

```markdown
---
name: blocker
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Skill"
      hooks:
        - type: command
          command: |
            tool_input=$(cat)
            skill_name=$(echo "$tool_input" | grep -o '"name":"[^"]*"' | head -1)
            if echo "$skill_name" | grep -q "block-me"; then
              echo '{"decision":"block","reason":"blocker prevents block-me from running"}'
            fi
---

# blocker

Invoke me first, then any subsequent attempt to invoke "block-me" skill will be blocked.

​```bash
echo "blocker armed"
​```
```

**`skills/block-me/SKILL.md`：**

```markdown
---
name: block-me
user-invocable: true
---

# block-me

If I get blocked by "blocker", I won't run.

​```bash
echo "block-me ran successfully"
​```
```

**実行：**

```
User: /my-plugin:blocker    ← ステップ 1: blocker を invoke
Output:
  blocker armed
                            ← この時点で blocker の frontmatter hook が登録される

User: block-me skill を起動してください   ← ステップ 2: 自然言語経由！
Output:
  blocker prevents block-me from running   ← block decision の reason
```

ポイント：
- ステップ 2 は **自然言語経由**でないと PreToolUse:Skill hook が発火しない（§1.9 参照）
- ステップ 1 は slash 経由でも自然言語でも OK（自分自身は block されない、§1.8 参照）

### 実用上の落とし穴

- block 対象 skill を **slash 経由** (`/foo:bar`) で起動された場合、§1.9 により Skill tool を経由しないので block 不発になる
- 自然言語経由（「`bar` を起動して」）の方しか確実に止められない
- README で block ルールを明示しないとユーザが混乱する

## 1.12 二層 trust モデル：skill は低信頼、plugin-level hook は高信頼

Claude Code の plugin 設計には明示的な信頼境界の二層構造がある（実装ソースコメントから読み取れる）：

| 役割 | 主体 | 信頼度 | 渡される env / 値 |
|---|---|---|---|
| ユーザ／Claude が叩く入り口（指示書） | **skill** | 低 | プロセス状況次第（多くが空） |
| 永続的な裏方処理（state・MCP・LSP・監視・ガードレール） | **plugin-level hook / MCP server** | 高 | フル env、機密値含む |

### 物理的な根拠

- `hooks/hooks.json` の hook command は **plugin install 時に明示的に validate** される。書く人 = plugin 作者と同一視
- `skills/<name>/SKILL.md` は **ユーザがあとから持ち込み可能**（チャットに paste、別 plugin から借用、等）。書く人 = 信頼度低
- 機密 env を skill に渡さないのは「skill 経由で誰でも書ける指示書から API key が漏れる」を防ぐため

### 実装例：trust 境界に従った設計

**OK 設計：機密処理は plugin-level hook に集中、skill は薄い指示書**

```json
// hooks/hooks.json — 高信頼ゾーン
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [
        { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/fetch-api.sh\"" }
      ]}
    ]
  }
}
```

```sh
#!/bin/sh
# hooks/fetch-api.sh — ここで API secret を使う
curl -H "Authorization: Bearer $CLAUDE_PLUGIN_OPTION_API_SECRET" https://api.example.com/data \
  > /tmp/api-result.txt
# 出力を additionalContext として Claude に注入
echo "API fetched, see /tmp/api-result.txt"
```

```markdown
# skills/use-api/SKILL.md — 低信頼ゾーン

User: API データを処理してください

Read /tmp/api-result.txt and analyze the content.

​```bash
cat /tmp/api-result.txt
​```
```

→ skill は API secret を一切知らない。ファイル経由でデータだけ受け取る。

**NG 設計：機密値を skill body で扱おうとする**

```markdown
# skills/use-api-bad/SKILL.md

​```bash
# 動かない：${user_config.api_secret} は sensitive: true 付きなので、Claude Code 本体が
# skill body 置換の段階で block する。Bash tool に渡るのは:
#   curl -H "Authorization: Bearer [sensitive option 'api_secret' not available in skill content]" ...
# 機密値は漏れない代わりに、curl リクエストは失敗する。設計として誤り。
curl -H "Authorization: Bearer ${user_config.api_secret}" https://api.example.com/data
​```
```

### 実用上の含意

- 機密値や永続的状態は **plugin-level hook で扱う**
- skill body には機密が必要な処理を書かない（書いても動かない or 漏れる）
- 「skill = ユーザに見せる指示書」「hook = 信頼された裏方処理」と物理的に分離する設計を心がける

---

# 第 2 章：上記の論点について Cowork では何が変わるか

## 2.0 大前提：Cowork の architecture model

第 2 章の各節は、Cowork の architecture を理解していないと「なぜそうなる」が腑に落ちない。検証で判明した model は **3 層**：①Windows ホスト ②（このマシンでは）WSL2 Ubuntu サブシステム ③host-adjacent な Cowork VM。**plugin-level hook は②で、Bash tool は③で動く**。

### 構造図

```
┌──────────────────────────────────────────────────────────────┐
│ ① ユーザの Windows ホスト (例: LAPTOP-BKGB6100)               │
│    Claude Desktop = Windows ネイティブ process                │
│    hook の command (/bin/sh) を実行するため POSIX シェルが要る  │
│    → ホスト側で利用可能な WSL2 に委譲（このマシン固有）         │
│                                                              │
│  ┌────────────────────────────────────────────┐              │
│  │ ② WSL2 Ubuntu サブシステム（このマシン固有）│ ← plugin-    │
│  │   hostname=LAPTOP-BKGB6100 (WSL 既定=Win名) │   level hook │
│  │   HOME=/home/<user>                         │   はここで   │
│  │   PATH ∋ /usr/lib/wsl/lib, /mnt/c/Users/...  │   実行       │
│  │   /sessions/ は見えない                      │              │
│  │   /mnt/c 経由で Windows FS にも届く           │              │
│  └────────────────────────────────────────────┘              │
│                │ virtio-fs FUSE mount                          │
│                ↓                                              │
│  ┌────────────────────────────────────────────┐              │
│  │ ③ Cowork VM (host-adjacent, KVM/Hyper-V?)   │              │
│  │   hostname=claude                           │              │
│  │   /sessions/<codename>/                     │              │
│  │     ├─ mnt/.remote-plugins/plugin_<id>/    │              │
│  │     │   (host から ro mount)                │              │
│  │     ├─ mnt/outputs/  (host から rw mount)   │              │
│  │     └─ mnt/uploads/  (host から ro mount)   │              │
│  │   Bash tool (mcp__workspace__bash) 実行     │ ← ③ Bash tool│
│  └────────────────────────────────────────────┘              │
└──────────────────────────────────────────────────────────────┘

※ ②(WSL2) は「Windows ホストで Claude が POSIX シェルを必要としたとき
  に使うホスト側シェル」であって Cowork VM の一部ではない。ホスト OS が
  変われば②の実体も変わる（Mac ネイティブ shell 等）= 未検証。
```

### 観測根拠（実機で取った data）

**Hook 内で hostname を確認：**

```bash
# plugin-level hook command として:
bash -c 'echo "HOST=$(hostname); SESSIONS=$([ -d /sessions ] && echo yes || echo no); PATH=$PATH"'
```

→ Claude の context に出る output：

```
HOST=LAPTOP-BKGB6100
SESSIONS=no
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/usr/lib/wsl/lib:/mnt/c/Users/<user>/AppData/Local/...
```

→ **hook は Windows ホスト上の WSL2 Ubuntu で実行されている**。`/mnt/c/Users/<user>/...` という WSL mount path が PATH に含まれている。

**再確認（2026-05-29, `cowork-mp-disambig-probe`, GUI marketplace install, 新規 chat）：** top-level の `$VAR` は Cowork で literal のままになる（§2.2）ため、`bash -c` でラップして env を展開させ、WSL2 固有マーカーを観測した：

```
MP_DA_BASH_HOME=/home/kazukinagata          # WSL2 Ubuntu のホーム（VM なら /sessions/...、Windows なら C:\...）
MP_DA_BASH_HOST=LAPTOP-BKGB6100             # WSL2 既定の hostname（=Windows マシン名）。VM なら claude
MP_DA_BASH_PATH=...:/usr/lib/wsl/lib:...:/mnt/c/Users/knaga/...   # ← WSL2 限定パス。決定打
```

`/usr/lib/wsl/lib` は WSL2 ディストロ内にしか存在しないので、「Windows ホストの Claude Desktop が、この hook をユーザの WSL2 Ubuntu に投げて実行した」が確定する。**ただしこれは本検証機（Windows+WSL2）固有の事実**であり、冒頭「検証環境の前提」の通り Cowork の WSL 依存を意味しない。

**Bash tool 内で hostname を確認：**

```bash
$ hostname
claude
$ pwd
/sessions/modest-intelligent-lamport
$ ls /sessions/
adoring-admiring-albattani  bold-epic-hamilton  cli-00f8f26c  ...
(175 dir)
```

→ **Bash tool は Cowork VM 内で実行されている**。175 dir 蓄積されている事実から「ユーザ単位で 1 つの長期 VM」と判明。

**Mount table の確認：**

```bash
$ mount | grep sessions
/dev/sdc on /sessions type ext4 (rw,nosuid,relatime)
/mnt/.virtiofs-root/shared/c/Users/<user>/.../outputs on .../outputs type fuse (rw,...)
/mnt/.virtiofs-root/shared/c/Users/<user>/.../uploads on .../uploads type fuse (ro,...)
/mnt/.virtiofs-root/shared/c/Users/<user>/.../rpm/plugin_<id> on /sessions/.../mnt/.remote-plugins/plugin_<id> type fuse (ro,...)
```

→ `/sessions/<codename>/mnt/` 配下が **virtio-fs で host filesystem を bind mount** していることが確定。`/mnt/.virtiofs-root/shared/c/Users/<user>/...` が host の `C:\Users\<user>\...` の VM 内表現。

### Why this matters

この split で以下の挙動が **自動的に**説明される：
- §2.1 hook env から CLAUDE_PLUGIN_* が消えた → host 側の env を Claude Desktop が export していないだけ
- §2.7 file I/O 不可視 → hook が書く `/tmp/foo.txt` は WSL の /tmp、Bash tool が読む `/tmp/foo.txt` は Cowork VM の /tmp、別 namespace
- §2.8 path の Windows form → skill body の `${CLAUDE_PLUGIN_ROOT}` は Claude Desktop (Windows) が知っている install path に置換
- §2.10 PreToolUse block 不発 → hook の decision が host から VM までネットワーク越しに届かない、または VM 側で無視している
- §2.13 trust 境界 → plugin-level hook がホスト環境（本検証機では WSL2 ＋ `/mnt/c` 経由で Windows FS）への完全アクセスを持つ（!）

## 2.1 環境変数の伝播（§1.1 の Cowork 版）

CLI では plugin-level hook と skill frontmatter hook に `CLAUDE_PLUGIN_ROOT` 等が SET されていた。**Cowork ではこれが UNSET になっている**（regression）。

### 実装例

§1.1 と同じ probe を Cowork で動かすと：

```json
// hooks/hooks.json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__workspace__bash",
        "hooks": [
          { "type": "command",
            "command": "bash -c 'echo \"[plugin-level] ROOT=[$CLAUDE_PLUGIN_ROOT]\"'" }
        ]
      }
    ]
  }
}
```

期待（CLI）: `[plugin-level] ROOT=[/path/to/plugin]`
実際（Cowork）: `[plugin-level] ROOT=[]`

`bash -c` で wrap してシェル展開が動くようにしても、env var そのものが set されていないので空文字列が出る。

### 観測根拠

probe 18 (data-readback) で：

```
HOOK_HOST_ROOT=
HOOK_HOST_DATA=
HOOK_HOST_REMOTE=
HOOK_HOST_HOSTNAME=LAPTOP-BKGB6100
HOOK_HOST_SESSIONS_DIR_EXISTS=no
```

すべて空。`CLAUDE_PLUGIN_ROOT` `CLAUDE_PLUGIN_DATA` `CLAUDE_CODE_REMOTE` が hook subprocess env に渡されていない。

### 再検証（2026-05-27, `cowork-env-probe`）

専用の最小 probe (`cowork-env-probe/`) を新規に作り、`bash -c` で `echo "...$CLAUDE_PLUGIN_ROOT..."` を出す plugin-level SessionStart hook で再観測した。結果は同一：

```
[PLUGIN-HOOK SessionStart] ROOT=[] DATA=[] PROJECT=[] OPT_HELLO=[] ENTRY=[] HOST=[LAPTOP-BKGB6100]
```

CLI で同 probe を動かした対照（baseline）：

```
[PLUGIN-HOOK SessionStart] ROOT=[/.../cowork-env-probe] DATA=[/.../plugins/data/cowork-env-probe-...] PROJECT=[/.../analyzing-claude-plugin] OPT_HELLO=[hello-from-CLI-baseline] ENTRY=[cli] HOST=[LAPTOP-BKGB6100]
```

→ CLI ではフル env + userConfig 値が来るが、Cowork plugin-level hook では全て空。`OPT_HELLO`（userConfig）も Cowork plugin-level hook には来ない。同一 probe を両環境で動かしているので、これは probe の不備ではなく Cowork 固有の挙動差で確定。

### plugin-level PreToolUse / skill frontmatter hook が Cowork で surface しない（2026-05-27 新観測）

同 probe で plugin-level PreToolUse hook、skill frontmatter hook（SessionStart matcher / PreToolUse matcher の両方）を仕込んだが、**Cowork ではいずれの出力も context に surface しなかった**（session resume で SessionStart を再発火させても frontmatter hook は出ない）。一方 CLI では同 probe の frontmatter PreToolUse hook が `ROOT=実パス DATA=空 PROJECT=実パス` で正常発火（§1.1 の「frontmatter hook は ROOT/PROJECT は来るが DATA は来ない」とも一致）。

つまり Cowork で stdout が context に surface する hook は **plugin-level SessionStart だけ**で、plugin-level PreToolUse / skill frontmatter hook（event 種別を問わず）は出てこない。詳細は §2.9・§2.10 を参照。skill frontmatter hook 経由で env を観測する手段が Cowork には無いため、「frontmatter hook で env が消える」という言い方より「frontmatter hook がそもそも Cowork で発火 / surface しない」と捉える方が観測に忠実。

### CLI と Cowork を分岐する方法

env 経由が死んでいるので、別の手で判定する：

```sh
# hook 内で
if [ "$(hostname)" = "claude" ]; then
  # Cowork
else
  # CLI (or other host)
fi

# あるいは
if [ -d /sessions ]; then
  # 何かが /sessions 配下で動いている = Bash tool 経路
else
  # hook 経路 (= local host)
fi
```

### 実用上の含意

- Cowork で plugin-level hook から plugin install dir を取得する手段は**ほぼ消失している**。`${CLAUDE_PLUGIN_ROOT}` は §1.2 で判明した通り hook command では**事前置換ではなく env シェル展開**で解決されるが、その env が Cowork では空（§2.1）。pre-sub の fallback も無い（hook command の `${CLAUDE_PLUGIN_*}` は元々 pre-sub 対象外）
- 後述 2.2 の通り top-level の `$` も抑止されるので、`${CLAUDE_PLUGIN_ROOT}` は literal、`bash -c` で wrap しても env 空なので空文字列
- CLI/Cowork 両対応の plugin は `bash -c` + hostname 判定で動作を分岐する設計が必要

## 2.2 `${VAR}` 置換と shell expansion（§1.2 / §1.3 の Cowork 版）

最大の落とし穴。Cowork の plugin-level hook command の `$VAR` 展開は top-level と `bash -c` wrap で挙動が分かれる：

| hook command の書き方 | shell 実行 | `$VAR` / `${VAR}` の扱い |
|---|---|---|
| **top-level** `echo X` | **される**（`/bin/sh`=dash。echo builtin・`&&`/`\|\|`・`[[` が動く） | **`$VAR` / `${VAR}` の展開だけが抑止され literal のまま** |
| **`bash -c "..."` で wrap** | 実 bash subprocess 起動 | フル POSIX 展開（`$VAR` も `${VAR}` も期待通り） |

> ⚠ **訂正（2026-05-27, `cowork-expansion-probe` で再検証）**：以前ここには「top-level は shell プロセス起動なしの literal text emission」と書いていたが、これは誤り。専用 probe で観測したところ、top-level command も `/bin/sh` で実行されていた：
> - `echo EXP_TOP_DOLLAR=$PATH` → stdout は `EXP_TOP_DOLLAR=$PATH`（"echo" が消えている = echo builtin が走った。`$PATH` だけ展開されず）
> - `[[ -d /tmp ]] && echo TRUE || echo FALSE` → stdout は `EXP_BRACKET_FALSE`（`&&`/`||`/`[[` が評価され、dash は `[[` 非対応なので `||` 側へ。command literal は出ない）
> - `bash -c 'echo $PATH'` → 実 PATH（bash で展開）
>
> CLI baseline では同 probe の top-level `echo $PATH` が実 PATH に展開された。**CLI は `$` を生で /bin/sh に渡す / Cowork は `$` を抑止して /bin/sh に渡す**、という違い。bracket が両環境とも FALSE なのは host 側 hook シェルが dash で `[[` 非対応だから（§1.3）であり、`/tmp` の有無とは無関係。
>
> 実用上の結論（「変数を使うなら `bash -c` で wrap」）は変わらない。誤っていたのは「shell を経ていない」というメカニズムの説明だけ。

### 実装例：5 通りの構文で PATH を参照する

**`hooks/hooks.json`：**

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "echo EXP_CONTROL_LITERAL=hello_world_static" },
          { "type": "command", "command": "echo EXP_TOP_DOLLAR=$PATH" },
          { "type": "command", "command": "echo EXP_TOP_BRACE=${PATH}" },
          { "type": "command", "command": "bash -c \"echo EXP_BASH_DOLLAR=$PATH\"" },
          { "type": "command", "command": "bash -c \"echo EXP_BASH_BRACE=${PATH}\"" }
        ]
      }
    ]
  }
}
```

Cowork で発火させて Claude の context を確認すると：

```
EXP_CONTROL_LITERAL=hello_world_static                    ← 定数、当然出る
EXP_TOP_DOLLAR=$PATH                                       ← literal！expansion されない
EXP_TOP_BRACE=${PATH}                                      ← literal！expansion されない
EXP_BASH_DOLLAR=/usr/local/sbin:/usr/local/bin:...        ← 展開されている
EXP_BASH_BRACE=/usr/local/sbin:/usr/local/bin:...         ← 展開されている
```

つまり：
- top-level: `/bin/sh` で実行はされる（echo / `&&` / `[[` は動く）が、`$VAR` 展開だけが抑止される（§2.2 冒頭の訂正参照）
- `bash -c "..."`: 実 bash が起動 → POSIX 通りに `$VAR` も展開される

### 実装例：${CLAUDE_PLUGIN_ROOT} を hook で使いたい場合

**NG（top-level）：**

```json
{
  "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/my-script.sh\""
}
```

→ Cowork では `$` 展開が抑止される + env も空なので、literal `${CLAUDE_PLUGIN_ROOT}/hooks/my-script.sh` を起動しようとして失敗（`cowork-presub-probe` で `${CLAUDE_PLUGIN_ROOT}` が literal のままと確認）。なお `${CLAUDE_PLUGIN_ROOT}` は事前置換対象ではなく env シェル展開対象（§1.2 の訂正参照）なので、CLI でも env が来ているから解決しているだけ。

**OK（bash -c で wrap）：**

```json
{
  "command": "bash -c '\"$CLAUDE_PLUGIN_ROOT/hooks/my-script.sh\"'"
}
```

→ ただし §2.1 で見た通り `$CLAUDE_PLUGIN_ROOT` 自体が空なので、結局 `/hooks/my-script.sh` を起動しようとして失敗する。

**Cowork 向けの現実的な対策**：hook 内で plugin install dir を find で localize する：

```json
{
  "command": "bash -c 'plugin_dir=$(find /sessions -path \"*/plugin_*\" -type d -maxdepth 5 2>/dev/null | head -1); echo \"plugin_dir=$plugin_dir\"'"
}
```

→ ただしこれも hook が **host machine** で実行されることを思い出すと、`/sessions/` は host には存在しない。hook 内で plugin install path を取る手段は事実上消えている。

### 朗報：`&&` / `||` が動くようになった

研究 v2.1.119 では「Cowork では `bash -c "true && echo X"` の `&&` が outer parser に分断されて動かない」とされていたが、**v2.1.146-148 では `&&` `||` が `bash -c` 内で正常に動く**ようになった（DOC-ALIGNED）。

```json
{
  "command": "bash -c \"[ -f /etc/hostname ] && echo file_exists || echo file_missing\""
}
```

→ 期待通り動く。`printf` 等の echo/bash 以外の builtin は依然 reject される。

### 実用上の対策

- Cowork hook command で何らかのロジックを書きたいなら **必ず `bash -c "..."` で wrap**
- 単純な定数 echo は top-level でも OK
- top-level command で `${...}` を書くと「動作確認しても期待した値が context に出ない、literal が出る」という事象になる。最初に踏みがちな罠

### 追検証：GUI marketplace install 経路（2026-05-29, `cowork-mp-script-probe/`）

§2.1 / §2.2 はこれまで全て **zip upload 経路**で観測したものだった。Claude Desktop の GUI から「marketplace add → install」する経路（zip upload とは別 UI）でも同じ挙動かを `cowork-mp-script-probe` で測った。

5 観測点（plugin-level SessionStart hook、新規 Cowork chat）：

| 観測点 | zip upload (既知) | GUI marketplace (今回) |
|---|---|---|
| `MP_SCRIPT_CONTROL=static_marker_no_var`（静的 echo） | 出る | 出る |
| `MP_SCRIPT_ECHO_BARE=${CLAUDE_PLUGIN_ROOT}`（top-level 裸） | literal | literal |
| `MP_SCRIPT_ECHO_SQ='${CLAUDE_PLUGIN_ROOT}'`（top-level single-quote） | literal | literal |
| `"${CLAUDE_PLUGIN_ROOT}/hooks/marker.sh" topbare`（top-level script 起動） | marker 行出ない | marker 行出ない |
| `bash -c '"$CLAUDE_PLUGIN_ROOT/hooks/marker.sh" bashbrace'`（bash -c wrap） | marker 行出ない | marker 行出ない |

→ **5 観測点すべて完全一致**。`${CLAUDE_PLUGIN_ROOT}` の hook command 内 resolution が壊れているのは install path 依存ではなく Cowork 共通制約。§2.1 / §2.2 を「Cowork 全 install 経路で成立」へ一般化できる。

副次観察：`MARKER form=topbare` も `MARKER form=bashbrace` も marker.sh の echo が一切 surface しないので、**hook command の exec 失敗（"No such file" 等の /bin/bash stderr）は context に届かない**。失敗を観測したければ呼び出し側で `&&` / `||` の echo 哨戒を仕込んで明示的に弾く必要がある（後述「`&&` / `||` が動くようになった」と組み合わせる）。例：

```json
{ "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/marker.sh\" topbare && echo MARKER_topbare=ok || echo MARKER_topbare=fail" }
```

これなら exec 失敗時に `MARKER_topbare=fail` が surface して silent failure を可視化できる（top-level `&&`/`||` は本節下流で動作確認済み、`$?` 等の変数展開は依然 dead なので静的文字列のみ）。**ただし `cowork-mp-script-probe` の session-export 解析（後述 §2.2bis）で hook stderr / exitCode は debug ログに完全記録されることが分かったので、まず session-export を見るのが最速**。

### モデル訂正：「`$` 抑止」ではなく「path 文脈だけ独自 substitution、それ以外は literal 素通し」（2026-05-29, session-export 解析）

§2.2 冒頭の訂正で「top-level command は `/bin/sh` 実行されるが `$VAR` 展開だけ抑止される」と書いていたが、`cowork-mp-script-probe` の session-export zip（後述 §2.2bis）に残った hook attachment を見直すと、より正確には：

| hook command (hooks.json literal) | session-export 内 stdout / stderr | 実 exec attempt | 何が起きたか |
|---|---|---|---|
| `echo MP_SCRIPT_ECHO_BARE=${CLAUDE_PLUGIN_ROOT}` | stdout: `MP_SCRIPT_ECHO_BARE=${CLAUDE_PLUGIN_ROOT}\r\n` | echo が走った | **`${CLAUDE_PLUGIN_ROOT}` が literal で残る** ＝ shell の env 展開が走っていない（走れば §2.1 通り empty で `MP_SCRIPT_ECHO_BARE=` に化けるはず） |
| `echo 'MP_SCRIPT_ECHO_SQ=${CLAUDE_PLUGIN_ROOT}'` | stdout: `'MP_SCRIPT_ECHO_SQ=${CLAUDE_PLUGIN_ROOT}'\r\n`（single-quote 込み） | echo が走った | single-quote 残存（補助観察。これ単独だと logger の re-quote 仮説が排除できないが、ECHO_BARE と整合する） |
| `"${CLAUDE_PLUGIN_ROOT}/hooks/marker.sh" topbare` | stderr: `/bin/bash: /hooks/marker.sh: No such file or directory`, exit 127 | bash が `/hooks/marker.sh` を exec しようとした | **path 先頭の `${CLAUDE_PLUGIN_ROOT}` だけ空文字列に置換された**（quote 剥がし + 置換、arg `topbare` は残った） |
| `bash -c '"$CLAUDE_PLUGIN_ROOT/hooks/marker.sh" bashbrace'` | stderr: `/bin/bash: line 1: /hooks/marker.sh: ...`, exit 127 | inner bash が `/hooks/marker.sh` を exec しようとした | 外側は素通し、内側 bash の `$CLAUDE_PLUGIN_ROOT` 展開で empty に化けた |

決定的観察：**ECHO_BARE の stdout に literal `${CLAUDE_PLUGIN_ROOT}` がそのまま残っている**。もし通常の shell が parse していたら、§2.1 で確定の通り `CLAUDE_PLUGIN_ROOT` が plugin-level hook 環境では空なので、env 展開で **`MP_SCRIPT_ECHO_BARE=`** に化けるはず。literal で残ったということは、`${...}` 部分が shell の手に渡る前に何らかの形で literal pass-through されている。

補助観察として ECHO_SQ の single-quote も残存しているが、これだけでは「logger が再 quote した」可能性を排除できず disambiguator としては弱い。決定的なのは ECHO_BARE の literal `${...}` 残存。

### 追検証：disambig probe で「shell parse 不在」を確定（2026-05-29, `cowork-mp-disambig-probe/`）

§2.2 のモデル訂正では「(a) shell bypass / (b) bash -c + `$`/`"` aggressive escape」のどちらか不明と保留していた。`cowork-mp-disambig-probe` で 8 観測点を仕込んで GUI marketplace install 経路で実機検証した結果（session-export zip 解析）：

| hooks.json command | session-export stdout | 評価 |
|---|---|---|
| `echo MP_DA_CONTROL=static_marker_no_var` | `MP_DA_CONTROL=static_marker_no_var\r\n` | 静的、surface 確認 |
| `echo MP_DA_DQ="double-quoted"` | `MP_DA_DQ="double-quoted"\r\n` | **double-quote literal 残存** |
| `echo MP_DA_DQ_INNER=hello-"middle"-world` | `MP_DA_DQ_INNER=hello-"middle"-world\r\n` | **inner quote も literal** |
| `echo MP_DA_HOME=$HOME` | `MP_DA_HOME=$HOME\r\n` | **`$HOME` literal**（HOME は env に必ず値ある変数） |
| `echo MP_DA_HOME_BRACE=${HOME}` | `MP_DA_HOME_BRACE=${HOME}\r\n` | brace 形も literal |
| `echo MP_DA_PATH=$PATH` | `MP_DA_PATH=$PATH\r\n` | **`$PATH` literal** |
| `echo MP_DA_NUL=$NO_SUCH_VAR_EXPECT_EMPTY` | `MP_DA_NUL=$NO_SUCH_VAR_EXPECT_EMPTY\r\n` | **unset var が literal**（shell parse なら empty 化けるはず） |
| `bash -c 'echo MP_DA_BASH_HOME=$HOME'` | `MP_DA_BASH_HOME=/home/kazukinagata\n` | **inner bash でのみ POSIX 展開**（line ending も `\n` のみ） |

**確定事項**：

1. **top-level command で shell parser は走っていない**。決定打 3 つ：
   - `$HOME` literal：HOME は universally set。shell parse なら確実に展開される
   - `$PATH` literal：同上
   - `$NO_SUCH_VAR_EXPECT_EMPTY` literal：shell parse 経由なら unset → empty 化けて `MP_DA_NUL=` になるはず。literal で残った
2. **double-quote も consume されない**：shell parse 経由なら quote は剥がれる。残ったので no parsing 確定
3. **`bash -c '...'` wrap した内側は通常の POSIX bash**：`MP_DA_BASH_HOME=/home/kazukinagata` で実値展開

**未確定事項**：実装が以下のどちらかは観測上区別不能：

- **(a) shell bypass**：launcher 自前のトーカナイザで exec、shell が完全に介在しない（ただし topbare の stderr `/bin/bash: /hooks/marker.sh: ...` を見ると、少なくとも exec の最終段で bash は関与している）
- **(b) bash -c with aggressive escape**：すべての `$` / `"` を `\$` / `\"` に escape してから `bash -c '<escaped>'` に渡す。escape 後の bash 動作は (a) と区別不能

(a)/(b) いずれも結果は同じで、**実用上は等価**：「top-level command で `$VAR`・`${VAR}`・`"..."` は全部 literal、唯一 `${CLAUDE_PLUGIN_ROOT}/<path>` だけ launcher が path 先頭で独自に pre-sub（値は Cowork plugin-level hook 環境では empty）」。これ以上の disambiguation は launcher 実装ソースを見ない限り無理。

いずれにせよ launcher のいる layer で起きていることは：

1. **path 先頭の `${CLAUDE_PLUGIN_ROOT}/...` だけ独自に substitute**（事前置換）。値は Cowork plugin-level hook 環境では empty
2. **それ以外の `${...}` / `$VAR` / quote 記号は literal のまま** child process まで届く（少なくとも echo の引数中では env 展開を経ていない）
3. `bash -c '...'` で wrap した場合のみ、inner bash で通常の POSIX 展開が走る（env が空なので結果は empty に化けるが、機構自体は POSIX）

実用上の含意：

- **「Cowork は `$` を抑止する」は誤り**。実態は「launcher が path 形 `${CLAUDE_PLUGIN_ROOT}/...` だけ独自置換、それ以外は素通し」
- 素通しの結果として echo の引数中の `${...}` は literal のまま表示される（shell 展開を経ていない）
- 独自置換の **value は empty**（CLI では実 path だが Cowork plugin-level hook 環境ではそもそも `CLAUDE_PLUGIN_ROOT` が値を持たない、§2.1）
- 結果として `"${CLAUDE_PLUGIN_ROOT}/hooks/x.sh"` は `/hooks/x.sh` に化けて起動失敗

書き換え方針：**動的 path 解決は完全に諦め、静的 echo のみで context に情報を流す**設計にする。

### §2.2bis hook 失敗のデバッグ：session-export zip（2026-05-29 新規）

「Cowork で hook が silent に失敗する」というのは context への surface 観点では事実だが、**Claude Desktop は host 側に全 hook 実行の構造化記録を残している**。手段：

1. Claude Desktop 上で対象 Cowork session を「Export Session」（メニュー or 設定経由で zip 落とす）
2. zip 内の `<sessionId>.jsonl`（transcript）と `logs/cowork_host_loop_debug.log` を解析

#### 観測される構造（transcript jsonl の hook attachment）

各 hook command 実行ごとに 1 attachment が記録される：

```json
{
  "type": "hook_non_blocking_error",
  "hookName": "SessionStart:startup",
  "hookEvent": "SessionStart",
  "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/marker.sh\" topbare",
  "stdout": "",
  "stderr": "Failed with non-blocking status code: /bin/bash: /hooks/marker.sh: No such file or directory",
  "exitCode": 127,
  "durationMs": 1909
}
```

成功時は `type: "hook_success"` で stdout が同様に記録される。**つまり context には surface しないだけで、全 stdout/stderr/exitCode は完全に記録されている**。

attachment.type の値（観測済み）：
- `hook_success` — exit 0
- `hook_non_blocking_error` — exit 非 0、でも session 進行は止めない（non-blocking hook event の場合）

#### 観測される構造（cowork_host_loop_debug.log）

同じ情報が DEBUG ログ形式でも見える：

```
[DEBUG] Hooks: Checking first line for async: MP_SCRIPT_ECHO_BARE=${CLAUDE_PLUGIN_ROOT}
[DEBUG] Hook output does not start with {, treating as plain text
[DEBUG] "Hook SessionStart:startup (SessionStart) success:\nMP_SCRIPT_ECHO_BARE=${CLAUDE_PLUGIN_ROOT}\r\n"
[DEBUG] "Hook SessionStart:startup (SessionStart) error:\n/bin/bash: /hooks/marker.sh: No such file or directory\n"
```

`Read hooks.json for plugin <name>` で hook 読み込み元 path も見えるので、どの plugin install path で動いてるかも特定可能。

#### 解析スニペット例（jq）

```sh
unzip -o session-export-*.zip -d /tmp/se/
# 失敗 hook だけ
jq -c 'select(.attachment.type=="hook_non_blocking_error") | .attachment | {command, exitCode, stderr}' \
  /tmp/se/*.jsonl
# 特定 plugin の全 hook
jq -c 'select(.attachment.hookEvent != null and (.attachment.command|contains("PLUGIN_NAME"))) | .attachment' \
  /tmp/se/*.jsonl
```

#### stderr の形が exec 失敗種別を教える

| stderr の形 | 意味 |
|---|---|
| `/bin/bash: <path>: No such file or directory`（line prefix 無し） | top-level command の直接 exec が失敗（script-file mode に近い実行） |
| `/bin/bash: line 1: <path>: No such file or directory`（"line 1:" あり） | `bash -c '...'` 内の inner bash が exec 失敗 |
| `exit 127` | command not found 系全般 |

#### 実用上の含意

- **「Cowork hook はデバッグ不能」は誤り**。session-export zip で完全観測可能
- 開発時のループ：probe 修正 → re-install → Cowork 起動 → 数 prompt 走らせる → Export Session → zip 中 jsonl を `jq` で grep
- skill body と違って hook stdout/stderr は context に出さない設計だが、host 側には残る（隠蔽でなく分離）
- session-export 自体に PII 等が含まれる可能性があるので、外部共有時は注意（transcript には会話本体も含まれる）

## 2.3 hook 実行シェルとシェル機能（§1.3 の Cowork 版）

CLI も Cowork も hook 実行シェルは `/bin/sh`（host が WSL/Ubuntu なら dash）。§2.2 の訂正の通り、top-level command も Cowork で `/bin/sh` 実行される（`$VAR` 展開だけ抑止）ので、dash の機能制約は CLI と同じく効く。

### 実装例

**Cowork の top-level で `[[ ]]` を書くと？**

```json
{ "command": "[[ -d /foo ]] && echo yes" }
```

→ top-level でも `/bin/sh`（dash）で評価される。dash は `[[` 非対応なので `[[: not found` 相当で失敗し、`&&` 側がスキップされる（`cowork-expansion-probe` で `EXP_BRACKET_FALSE` を観測）。「literal で素通り」ではなく「dash で評価されて失敗」が正しい。

**Cowork で `bash -c` 経由なら `[[ ]]` も使える：**

```json
{ "command": "bash -c '[[ -d /foo ]] && echo yes'" }
```

→ 実 bash が `bash -c` で起動するので bash 構文が使える。`$VAR` 展開も復活する。

### 実用上の対策

- bash 固有構文は `bash -c '...'` 内なら安全に書ける（Cowork でも CLI でも）
- top-level command は echo の literal emission しか使えない、と割り切る

## 2.4 sensitive userConfig（§1.4 の Cowork 版）

Cowork には **そもそも userConfig UI が無い**。`/plugins` コマンド自体が存在せず、disable→enable のような操作も silent skip される。設定値が必要な plugin は Cowork で実質使えない。

### 実装例：userConfig を使わない設計

CLI 向け：

```json
// plugin.json
{
  "userConfig": {
    "api_secret": { "sensitive": true }
  }
}
```

Cowork でこれを使おうとすると：
- ユーザが zip を upload + enable
- `api_secret` を入力する UI は出ない（`/plugins` が無い）
- hook 内で `$CLAUDE_PLUGIN_OPTION_API_SECRET` を参照 → 空
- plugin が機能しない

### 代替設計：会話経由で値を取る

```markdown
# skills/configure/SKILL.md
---
name: configure
user-invocable: true
---

# configure

Tell me your API key. I'll store it in this session's context for use by other skills.

​```bash
read -p "Enter API key: " api_key
# but actually, the read doesn't work via Bash tool because stdin isn't interactive
# better: ask the user via chat, then a separate skill writes to outputs/
​```
```

実用的には：

1. ユーザに chat で「API key を教えて」と促す
2. ユーザが key を chat で送る
3. Claude が key を `outputs/api-key.txt` 等に書く（§2.15 の通り outputs/ は rw）
4. 後続 skill が `cat outputs/api-key.txt` で読む

ただし key を session に置く時点で **chat 履歴に key が残る**ことに注意。

### 実用上の対策

- Cowork 対応 plugin を作る場合、**userConfig に依存しない**設計にする
- どうしても設定が要るなら、初回起動時に Claude に「ユーザに API key を聞いてください」と指示する skill を用意する
- 永続化は §2.8 の通り Cowork では不可なので、毎 chat で再入力させる前提でフローを組む

## 2.5 userConfig trigger（§1.5 の Cowork 版）

§2.4 の通り、Cowork では trigger 経路がすべて死んでいる。CLI で確認されていた「`/plugins` UI から入力」「disable→enable で参照あり&未設定なら prompt」のいずれも Cowork では発生しない。

加えて、Cowork で `${user_config.KEY}` を含む SessionStart hook の配列を仕込むと、参照 entry だけが **silent skip** される（CLI なら hook error が出る経路と差別化されている）。

### 実装例

```json
// hooks/hooks.json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "echo 'entry 0: always runs'" },
          { "type": "command", "command": "echo 'entry 1: ${user_config.my_key}'" },
          { "type": "command", "command": "echo 'entry 2: always runs'" }
        ]
      }
    ]
  }
}
```

CLI（`my_key` 未設定）：
- entry 0 が走る
- entry 1 で `${user_config.my_key}` が literal で `/bin/sh` に渡る → 何か壊れる、または `Plugin option "my_key" isn't set.` エラー
- entry 2 は走るかどうか不定

Cowork（`my_key` 未設定）：
- entry 0 が走る → context に "entry 0: always runs"
- entry 1 は **silent skip** → 何も context に出ない、エラーも出ない
- entry 2 は走る → "entry 2: always runs"

silent skip は debug が極めて難しい挙動。

### 再検証：機密×必須の全 4 組み合わせ（2026-05-27, `cowork-userconfig-probe/`）

`opt_plain`（非機密・任意）/ `req_plain`（非機密・必須）/ `opt_secret`（機密・任意）/ `req_secret`（機密・必須）の 4 userConfig を宣言し、CLI と Cowork で挙動を比較した。

**CLI 側（trigger のタイミング）：**

| タイミング | 挙動 |
|---|---|
| `claude plugin install`（required 未設定） | warning「4 userConfig options not yet set (2 required)」のみ。**install は block しない**。`required: true` を認識して "(2 required)" とカウントする |
| `claude` 起動のみ | **silent**（required 未設定でも自動プロンプトなし） |
| `/plugin configure` 明示実行 | 対話 UI が出る。**required 項目に `*` マーク**（`Required plain*` 等）、optional は無印 |
| **disable → enable** | **入力 UI が自動で出る**（§1.5 の trigger を required 付きで再現） |

→ CLI の `required: true` は「強制」ではなく「UI ヒント（`*`）+ install warning + disable→enable trigger」。install を block も自動プロンプトもしない。

**Cowork 側：**

| 観察 | 結果 |
|---|---|
| install 時の required プロンプト | **出ない**（完全に無視） |
| `/plugin configure` 相当 UI | **存在しない** |
| **disable → enable での入力 UI** | **出ない**（CLI では出るのに Cowork では出ない＝入力経路ゼロ） |

値を set する手段が一つも無いので、全 4 組が常に unset。その状態の runtime 解決（uc-check）：

| combo | skill body（pre-sub） | plugin-level hook |
|---|---|---|
| `opt_plain`（非機密・任意） | literal `${user_config.opt_plain}` | 行が出ない（silent skip） |
| `req_plain`（非機密・必須） | literal `${user_config.req_plain}` | 行が出ない |
| `opt_secret`（機密・任意） | `[sensitive option 'opt_secret' not available in skill content]` | 行が出ない |
| `req_secret`（機密・必須） | block 文字列 | 行が出ない |
| control（変数なし） | — | `UC-HOOK control=static_marker`（出る） |

→ **required/optional の区別は Cowork の runtime に影響しない**（UI が無いので値は常に unset）。機密軸だけが body で block を生む（§1.4 が Cowork でも有効）。CLI で全 4 値を set した対照では、body は非機密=実値 / 機密=block、plugin-level hook は **4 つとも平文**（機密も平文で plugin-level に来る、§1.4）だった。

記事の「`/plugin configure` UI が Cowork に無い」は再現。さらに **disable→enable trigger も Cowork では死んでいる**ことが分かり、「Cowork には userConfig 入力経路が一つも無い」という強い形になる。

### 実用上の対策

- Cowork では `${user_config.KEY}` を hook command に書かない
- 必要な値は skill body で Claude に教えさせる経路を取る

## 2.6 marketplace cache（§1.6 の Cowork 版）

Cowork でも **marketplace 登録と marketplace 経由の plugin install は機能する**（Claude Desktop UI 側で marketplace add → plugin install のフローが提供されている）。ただし手元の zip を直接アップロードする経路も併存していて、開発中はこちらで反復することが多い。zip 経路の場合「zip を再生成 → 再 upload」のループになる（CLI の `claude plugin install` のように source dir を edit したら即反映、というわけにはいかない）。

なお OTel event の `marketplace_name` field は zip 経路の場合 `inline` 固定になる（§B.3 参照）。marketplace 経由 install ならその marketplace 名が入る。

### 実装例：開発時の zip 生成

```sh
#!/usr/bin/env bash
# scripts/package-cowork.sh
cd "$(dirname "$0")/.."
mkdir -p findings/dist
( cd verifier && zip -r ../findings/dist/verifier-cowork.zip . \
    -x '.git/*' '*.pyc' 'findings/*' )
echo "Upload findings/dist/verifier-cowork.zip via Claude Desktop"
```

### Cowork に upload 後の plugin 配置

`/sessions/<codename>/mnt/.remote-plugins/plugin_<id>/` に展開される（read-only mount）。`<id>` は upload 毎に新規 ID が振られるので、bisect で id を追える。

```bash
$ ls /sessions/eloquent-pensive-cerf/mnt/.remote-plugins/
plugin_014ceSFqzvfVQjArXGEQm98s
plugin_0155zZVATbJU3jHUmPP9NvMC
plugin_016wgiSBoyPhGDjfxTrFRJg8
plugin_01Bf44yjuV9jiutc7dYNcHHc  ← 今回 upload した plugin
```

### 実用上の対策

- Cowork での反復開発は CLI と比べて遅い。CLI で reasonable に動くところまで詰めてから Cowork upload する
- ただし後述 §2.16 の通り Cowork validator は CLI より厳しいので、CLI 通過 ≠ Cowork install 可能。CI に Cowork 実機 upload テストを組み込む必要がある

## 2.7 skill body の `${VAR}` 置換（§1.7 の Cowork 版）

skill body 内の `${CLAUDE_PLUGIN_ROOT}` `${CLAUDE_PLUGIN_DATA}` 置換は **Cowork でも機能する**。ただし置換される値は **ホスト Windows 側の絶対パス**。

### 実装例

**`skills/path-readback/SKILL.md`：**

```markdown
---
name: path-readback
user-invocable: true
---

# path-readback

​```bash
echo "BODY_SUBST_ROOT=${CLAUDE_PLUGIN_ROOT}"
echo "BODY_SUBST_DATA=${CLAUDE_PLUGIN_DATA}"
echo "BODY_SUBST_SKILL_DIR=${CLAUDE_SKILL_DIR}"
​```
```

Cowork で invoke すると Claude が実行する bash の中身（context にロードされた時点）：

```
echo "BODY_SUBST_ROOT=C:/Users/<user>/AppData/Roaming/Claude/local-agent-mode-sessions/<sess-uuid>/<inner-uuid>/rpm/plugin_<id>"
echo "BODY_SUBST_DATA=C:/Users/<user>/AppData/Roaming/Claude/.../local_<sess-uuid>/.claude/plugins/data/<plugin-name>-inline"
echo "BODY_SUBST_SKILL_DIR=C:/Users/<user>/AppData/Roaming/Claude/.../rpm/plugin_<id>/skills/path-readback"
```

これを Bash tool（host-adjacent VM 側で動く）で実行すると：

```
BODY_SUBST_ROOT=C:/Users/<user>/...
BODY_SUBST_DATA=C:/Users/<user>/...
BODY_SUBST_SKILL_DIR=C:/Users/<user>/...
```

→ **Windows パス文字列がそのまま echo されるだけ**。これを `bash` に渡すと host-adjacent VM の filesystem には存在しないので失敗する：

```bash
$ bash "${CLAUDE_PLUGIN_ROOT}/scripts/say-hi.sh"
bash: C:/Users/<user>/.../scripts/say-hi.sh: No such file or directory
```

### ただし Read tool はこの Windows パスを読める（tool 別の差、2026-05-27 Cowork 観察）

「Bash で使えない」のは VM 側 shell が Windows パスを解決できないからで、**file tool（Read / Write / Edit）は別の話**。Cowork で skill body の `${CLAUDE_PLUGIN_ROOT}/<file>`（= host Windows パス）を各 tool で叩いた結果：

| tool | host Windows パス（plugin install dir）への動作 |
|---|---|
| **Read** | ✅ **読める**（接続フォルダ外でも。Read tool は広範な FS アクセスを持ち、virtio-fs 経由で host ファイルに届く） |
| **Write** | ❌ ブロック（接続フォルダ外への書き込み不可） |
| **Edit** | ❌ ブロック（同上。先に Read していても不可） |
| **Bash** | ❌ 不可（VM 側 shell、Windows パス不在） |

実用上の含意：
- **plugin の同梱ファイルを「読む」だけなら、skill body の `${CLAUDE_PLUGIN_ROOT}/<file>` を Read tool でそのまま読める**（下記 `find /sessions` の localize は不要）。CHANGELOG や設定テンプレートを参照する用途はこれで足りる
- 「実行」(Bash) や「書き換え」(Write/Edit) は不可。実行したいなら下記の localize、書き換えは plugin dir 外なので諦める（§2.15 の「plugin dir は read-only / 接続フォルダ外は書けない」と整合）

> ※ この tool 別マトリクスは Cowork セッションでの観察に基づく（追試 probe は未実施だが、`${CLAUDE_PLUGIN_ROOT}` を body に持つ任意の skill で Read/Write/Edit/Bash を 1 プロンプトずつ叩けば再現できる）。

### Cowork で bundled script を実行する正しい方法（Bash で実行したい場合）

`find /sessions` で host-adjacent VM 側の mount path を localize：

```markdown
​```bash
# Cowork compatible: locate plugin mount path inside the VM
skill_dir=$(find /sessions -path '*/skills/path-readback' -type d 2>/dev/null | head -1)
if [ -n "$skill_dir" ]; then
  cd "$skill_dir" && bash scripts/say-hi.sh
else
  # CLI fallback: use ${CLAUDE_SKILL_DIR} directly
  bash "${CLAUDE_SKILL_DIR}/scripts/say-hi.sh"
fi
​```
```

### 実用上の対策

| やりたい操作 | Cowork での書き方 |
|---|---|
| bundled script を Bash tool から起動 | `${CLAUDE_PLUGIN_ROOT}` は使わず、`find /sessions -path '*/skills/<name>' -type d` で host-adjacent VM 側の mount path を localize してから cd + 相対 path |
| `${CLAUDE_PLUGIN_DATA}` への永続化 | できない。§2.8 参照 |
| Windows path を bash で `mkdir -p` | **危険**：bash は `:` を path separator として解釈しないので、`mkdir -p "C:/foo"` は **`$PWD/C:/foo` というゴミディレクトリを silent に作る**。必ずガードを入れる：`[[ "$path" =~ ^[A-Z]: ]] && return 1` |

## 2.8 hook と Bash tool は完全に別の filesystem（§1.7 の派生）

Cowork architecture が原因で、**plugin-level hook が書いたファイルは Bash tool 側からは見えない**。

理由：
- plugin-level hook はホスト側シェル（本検証機では WSL2 Ubuntu）で実行される
- Bash tool は host-adjacent VM で実行される
- 両者は別の filesystem namespace（hook が触る `/tmp` は WSL2 の `/tmp`、VM の `/tmp` とは別物）

> 再検証（2026-05-27, `cowork-fs-probe/`）：SessionStart hook で `/tmp/cowork-fs-canary.txt` に書き込み（`bash -c` で実行、host 名込み）、skill body の Bash tool で `cat` を試した。
> - CLI baseline: hook host = body host = `LAPTOP-BKGB6100`、`cat` 成功（canary 内容が読めた）= 同一 filesystem
> - Cowork: body host = `claude`（VM）、`cat /tmp/cowork-fs-canary.txt` → `No such file or directory`、`ls` も同様
>
> 同一 probe で CLI は読める / Cowork は読めない。**記事の主張（hook=host / Bash tool=VM の別 filesystem）が実機で再現**。これは訂正不要の確認。

### 実装例

**hook 内で書き込む：**

```json
// hooks/hooks.json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "echo marker > /tmp/canary.txt" }
        ]
      }
    ]
  }
}
```

→ hook は **ホスト側シェル（本検証機では WSL2 Ubuntu）** で実行されるので `/tmp/canary.txt` は **WSL2 の `/tmp`**（Windows の temp でも VM の `/tmp` でもない）に書かれる。

**Bash tool 内で読もうとする：**

```markdown
# skills/read-canary/SKILL.md

​```bash
cat /tmp/canary.txt
​```
```

→ Bash tool は **Cowork VM** で実行されるので VM の `/tmp` を見る。ホスト側（WSL2）の `/tmp/canary.txt` は見えない。

```
$ cat /tmp/canary.txt
cat: /tmp/canary.txt: No such file or directory
```

### state を渡す唯一の手段：stdout → additionalContext

```json
// hooks/hooks.json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "echo 'STATE_MARKER=hello-from-hook'" }
        ]
      }
    ]
  }
}
```

→ hook の stdout は Claude の additionalContext に注入されるので、skill body で参照できる：

```markdown
# skills/use-state/SKILL.md

「STATE_MARKER」で始まる行が context にあるはずです。その値を bash で echo してください：

​```bash
echo "I received: STATE_MARKER=hello-from-hook"
​```
```

ただしこれは **session-scope（同一 chat 内）でしか有効ではなく**、永続化にも使えない。新規 chat では SessionStart hook が再度発火して別の context として再注入される（※ resume での再発火は実測済み、brand-new chat での再発火は cross-chat 隔離 §2.14 からの推論）。

### CLAUDE_ENV_FILE 経路も Cowork では使えない（2026-05-27, `cowork-envfile-probe/`）

CLI には stdout 以外にもう一つ hook→Bash tool の env 受け渡し経路がある：SessionStart 等の hook に渡される `$CLAUDE_ENV_FILE` に `export FOO=bar` を書くと、後続の Bash tool 呼び出しに env として渡る仕組み。これが Cowork で使えるか検証した。

- **CLI baseline**：hook env に `CLAUDE_ENV_FILE=/.../session-env/<sid>/sessionstart-hook-NN.sh` が set されており、そこに `export ENVFILE_MARKER=hello-from-envfile` を書くと、skill body の Bash tool で `$ENVFILE_MARKER=hello-from-envfile` が読めた（機構が動く）
- **Cowork**：単一 echo / 複数文 echo の SessionStart hook はどちらも context に surface したが、その出力は **`CLAUDE_ENV_FILE=[]`（空）**。つまり **Cowork の plugin-level hook には CLAUDE_ENV_FILE 自体が渡されていない**。書き込む先が無いので機構は起動すらできず、skill body の `$ENVFILE_MARKER` も `(unset)`。

→ §2.1 の「Cowork hook env から `CLAUDE_*` が消える」に `CLAUDE_ENV_FILE` も含まれる。結果、**hook→skill の state 受け渡しは stdout → additionalContext が唯一の経路**で確定（CLAUDE_ENV_FILE という代替も塞がれている）。

### ⚠ 重大な footgun：hook command に redirect があると stdout が surface しない（2026-05-27, `cowork-surface-probe/`）

その「唯一の経路」である stdout→additionalContext にも罠がある。SessionStart hook command の形を 5 variant で切り分けたところ、**command 文字列に redirect 演算子（`>` / `>>`）が含まれていると、その hook の stdout が丸ごと context に surface しなくなる**ことが判明した。

| variant | hook command の形 | Cowork で surface |
|---|---|---|
| V1 | `echo "..."`（単一） | ✅ |
| V2 | `echo a; echo b`（複数文） | ✅ |
| V3 | `echo x; if [ -n "$HOME" ]; then echo then; else echo else; fi`（if/else、redirect なし） | ✅ |
| V4 | `echo x; echo y >> /tmp/f; echo after`（**実行される redirect**） | ❌ **hook 全体が消失**（前後の echo も含めて） |
| V5 | `echo x; if [ -n "$CLAUDE_ENV_FILE" ]; then echo w >> "$CLAUDE_ENV_FILE"; ...; else echo else; fi`（**ガードで実行されない redirect**） | ❌ **hook 全体が消失** |

ポイント：
- **`if/then/else` 構造は無罪**（V3 が surface）。複数文も無罪（V2）。
- **redirect の有無だけが効く**。V4（redirect 実行）も V5（redirect が else 分岐で実行されない）も両方消える → **redirect トークンが command 文字列に存在するだけ**で、実行有無に関係なく hook の stdout 全体が捨てられる（Cowork 側が command を静的にスキャンして「出力を自前で管理する command」と判断している様子）。

実用上の含意：
- Cowork で hook の stdout を additionalContext として使いたいなら、**その hook command に `>` / `>>` を一切書かない**。`echo "info" && log >> /var/log/x` のような「ついでにログも吐く」hook は、Cowork では `info` も含めて無言で消える
- これは §2.8 で当初 `[ENVFILE-HOOK]`（`>> "$CLAUDE_ENV_FILE"` 入り）が surface しなかった真因。当初「stale chat か」と推測したが誤りで、redirect トークンが原因だった（fresh chat でも再現）

### 実用上の含意

- Cowork で「hook が状態を持って、後で skill が読む」というよくあるパターンは動かない
- 状態を渡す手段は stdout → additionalContext のみ（CLAUDE_ENV_FILE 経路も CLAUDE_ENV_FILE 自体が未設定なので不可）
- 永続化が必要な plugin は Cowork で別設計が必要（outputs/ にユーザの目に見える形で書く等）

## 2.9 skill frontmatter hook の登録タイミング（§1.8 の Cowork 版）

CLI では「一度 invoke した skill の frontmatter hook は `claude` プロセス終了まで生存」だった。Cowork では：

- skill frontmatter hook は **そもそも発火 / surface しない**（2026-05-27 `cowork-env-probe` で再検証）
- SessionStart matcher / PreToolUse matcher のどちらで仕掛けても、invoke 直後の同一プロンプトでも、session resume 後でも、frontmatter hook の出力は context に出てこない
- 対照的に CLI では同一 probe の frontmatter PreToolUse hook が body bash 実行時に正常発火する（§2.1 の再検証参照）

> ※ 以前は「1 プロンプト内のみ有効、VM suspend/resume で reset」と記述していたが、2026-05-27 の `cowork-env-probe` 再検証では invoke した同じプロンプトの body bash 実行時ですら frontmatter hook が発火しなかった。「1 プロンプト内は有効」という以前の見立ては Cowork では成立せず、より強く「frontmatter hook は Cowork で機能しない」が正しい。

### 実装例

CLI で動く §1.11 の blocker pattern：

```markdown
---
name: blocker
hooks:
  PreToolUse:
    - matcher: "Skill"
      hooks:
        - type: command
          command: 'echo "{\"decision\":\"block\",\"reason\":\"blocked\"}"'
---
```

CLI 運用：
1. ユーザが `/my-plugin:blocker` を起動 → hook 登録
2. 以降の全 skill 起動試行を block ✅

Cowork 運用：
1. ユーザが `/my-plugin:blocker` を起動 → hook 登録（次のプロンプトまで）
2. **次のプロンプト**を待つ間に何分か経過 → VM が suspend されて hook 失効
3. ユーザが何か入力 → hook 未登録、block 不発 ❌

### 実用上の対策

- Cowork で長期的な guard を仕掛けたいなら frontmatter hook ではなく plugin-level hook を使う（§2.10 の訂正の通り、plugin-level PreToolUse block は Cowork でも効く。ただし `${CLAUDE_PLUGIN_ROOT}` で外部スクリプトを呼ばず inline で書くこと）
- 「user の bash 試行を guard したい」系の plugin は Cowork で実質機能不能
- 諦めて skill body の冒頭でチェックを書く、または各 skill に inline で同じガードを置く

## 2.10 plugin-level PreToolUse block は Cowork でも効く（旧「無効化」結論を訂正）／ frontmatter は効かない

> 🔴 **重大訂正（2026-05-27, `cowork-blockmethods-probe/`）**：このセクションは当初「Cowork では plugin-level PreToolUse block が完全に死亡」と書いていたが、**誤り**。再検証の結果、**plugin-level PreToolUse block は Cowork でも効く**（3 つの documented 形式すべて）。旧結論は probe のバグによる artifact だった。

### 正しい結論：plugin-level PreToolUse block は Cowork で honor される

`cowork-blockmethods-probe` で、PreToolUse の 3 つの documented block 形式を inline hook（外部スクリプト不要・redirect なし）で試した：

| block 方式 | hook が emit するもの | CLI | Cowork |
|---|---|---|---|
| `decision:block`（レガシー） | `{"decision":"block","reason":"BLK-decision"}` | ブロック | **ブロック** |
| `hookSpecificOutput.permissionDecision:deny`（現行標準） | `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",...}}` | ブロック | **ブロック** |
| `exit 2` | exit code 2 | ブロック（hook error） | **ブロック（hook error）** |
| control（block なし） | — | 実行 | 実行 |

CLI でも Cowork でも、3 方式すべてが Bash tool 実行を阻止し、control だけが通った。**plugin-level PreToolUse の block は Cowork で機能する**。

### 旧結論が誤っていた理由

当初の probe 13（`hooks-block.json`）は block hook を次のように呼んでいた：

```json
{ "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/block.sh\" Bash blocked-by-plugin-level" }
```

`${CLAUDE_PLUGIN_ROOT}` は §2.1 の通り **Cowork hook command では空**（env シェル展開で解決されるが env が無い）。そのため Cowork では実際には `"/hooks/block.sh" ...` が起動され、**スクリプトが見つからず exit 127 → block decision が一切 emit されない** → Bash tool が普通に実行された。これを「Cowork が block を無視する」と誤読していた。実態は「**block スクリプトが Cowork で見つからず、そもそも block を出していなかった**」。

教訓：Cowork で block hook を書くなら **`${CLAUDE_PLUGIN_ROOT}` で外部スクリプトを呼ばず、block ロジックを hook command に inline で書く**（さらに redirect も入れない、§2.8 footgun）。これを守れば plugin-level block は Cowork で効く。

### 実装例（Cowork で効く形）

```json
// hooks/hooks.json — inline、外部スクリプト/${CLAUDE_PLUGIN_ROOT}/redirect なし
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|mcp__workspace__bash",
        "hooks": [
          { "type": "command",
            "command": "bash -c 'input=$(cat); case \"$input\" in *rm\\ -rf*) echo \"{\\\"decision\\\":\\\"block\\\",\\\"reason\\\":\\\"blocked rm -rf\\\"}\" ;; esac'" }
        ]
      }
    ]
  }
}
```

matcher は CLI (`Bash`) と Cowork (`mcp__workspace__bash`) の両対応で `Bash|mcp__workspace__bash`（§2.11）。

### skill-to-skill block（frontmatter PreToolUse:Skill）も Cowork では効かない（2026-05-27 実測で訂正）

以前は「skill frontmatter の `PreToolUse:Skill` による skill-to-skill block は Cowork でも生存（§1.11 ベースで動く）」と記述していたが、これは CLI 挙動からの**未検証の類推**だった。専用 probe (`cowork-block-probe/`) で実測した結果、**Cowork では frontmatter PreToolUse:Skill の block decision も honor されない**ことが確定した。

probe 構成：guard skill が frontmatter `PreToolUse:Skill` hook で `{"decision":"block","reason":"BLOCKED-BY-GUARD-HOOK"}` を返す → victim skill を自然言語で起動して止まるか観測。

| 環境 | victim 起動経路 | 結果 |
|---|---|---|
| CLI | Skill tool（自然言語） | `BLOCKED-BY-GUARD-HOOK` で**ブロック**、victim body 走らず |
| Cowork | Skill tool（`Launching skill: ...` 出る） | **ブロックされず** `VICTIM-RAN-MARKER ... host=claude` で victim body 実行 |

Cowork では Skill tool 呼び出し自体は起きているのに block が無視される。これは §2.9 の「Cowork で frontmatter hook が発火 / surface しない」とも整合（hook が機能しないので block decision も届かない）。

### 実用上の含意

- **「危険な bash コマンドを plugin が事前に止める」系の guard は、plugin-level PreToolUse hook なら Cowork でも効く**（§2.10 の訂正）。ただし block ロジックは hook command に inline で書くこと（`${CLAUDE_PLUGIN_ROOT}` 経由の外部スクリプトは Cowork で見つからず block が emit されない／redirect は §2.8 footgun で出力が消える）
- **skill-to-skill block（frontmatter PreToolUse:Skill）は Cowork では動かない**（2026-05-27 実測。frontmatter hook がそもそも発火しないため。CLI では動く）
- まとめると Cowork の block は **plugin-level PreToolUse = 効く / frontmatter PreToolUse = 効かない** の二分。guard は plugin-level に inline で実装する

## 2.11 Bash tool 名は `mcp__workspace__bash`

CLI では Claude が `Bash` tool を呼ぶ。Cowork では **`mcp__workspace__bash`**（MCP server 経由）。hooks.json で matcher を `"Bash"` のみで書いていると **Cowork で hook が発火しない**。

### 実装例：両環境対応 hook

```json
// hooks/hooks.json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "echo '[CLI bash about to run]'" }
        ]
      },
      {
        "matcher": "mcp__workspace__bash",
        "hooks": [
          { "type": "command", "command": "echo '[Cowork bash about to run]'" }
        ]
      }
    ]
  }
}
```

または regex で両方マッチ：

```json
{
  "matcher": "Bash|mcp__workspace__bash",
  "hooks": [
    { "type": "command", "command": "echo '[bash about to run, any env]'" }
  ]
}
```

### 実用上の対策

- 両環境対応の plugin にする場合、PreToolUse matcher を `"Bash"` と `"mcp__workspace__bash"` の両方で定義する
- もしくは `".*"` で全 tool を捕まえる（ただし他 tool 起動時にも発火するので過剰になる可能性）

## 2.12 並列発火（§1.10 の Cowork 版）

Cowork でも plugin-level の SessionStart 配列は並列発火する。CLI と同じく書込先ファイルの排他制御は必要。

ただし Cowork では §2.8 の通り file write 自体が Bash tool から見えないので、競合の影響は限定的。複数の hook が context に並列で文字列を出すと **Claude の context に並びが乱れた状態で injection される**ことには変わりない（順序保証なし）。

```json
// hooks/hooks.json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command", "command": "sleep 0.3 && echo 'A'" },
          { "type": "command", "command": "sleep 0.1 && echo 'B'" },
          { "type": "command", "command": "echo 'C'" }
        ]
      }
    ]
  }
}
```

Claude の context に並ぶ順は概ね `C, B, A`（sleep 短い順）。array 順 (A, B, C) ではない。

## 2.13 二層 trust モデルの拡張（§1.12 の Cowork 版）

Cowork の architecture を踏まえると、信頼境界はさらに複雑になる：

| 役割 | 実行場所 | 信頼境界 |
|---|---|---|
| skill body の bash | host-adjacent VM (sandbox) | sandbox 内に閉じ込められる |
| plugin-level hook | **ホスト側シェル（本検証機では WSL2 Ubuntu）** | **ホスト環境へのフルアクセスを持つ**（!!） |
| Bash tool subprocess | host-adjacent VM (sandbox) | sandbox 内 |

> ⚠ ここでの「ホスト環境へのフルアクセス」は本検証機（Windows+WSL2）では「WSL2 の Linux FS 全部 ＋ `/mnt/c` 経由の Windows ドライブ」を指す。下の例で `/mnt/c/Users/<user>/Documents` が読めるのは「WSL2 内 hook が WSL マウント越しに Windows FS に届く」から。ホスト OS が変われば到達面の具体形は変わるが、「hook は sandbox 外でホスト権限を持つ」という危険の本質は不変。

### 実装例：plugin-level hook が host にアクセスできる証拠

```json
// hooks/hooks.json — Cowork で動く
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command",
            "command": "bash -c 'echo HOST_FILES=$(ls /mnt/c/Users/<user>/Documents 2>&1 | head -5)'" }
        ]
      }
    ]
  }
}
```

Cowork で動かすと Claude の context に：

```
HOST_FILES=document1.docx document2.pdf 家計簿.xlsx my-secrets.txt ...
```

→ plugin-level hook は **ユーザの Documents フォルダの中身を完全に読める**。これは sandboxed VM ではなく、ホスト側シェル（本検証機では WSL2、`/mnt/c` 経由で Windows FS に到達）で実行されているから。

### 危険性

理論上 plugin 作者は plugin-level hook で：
- `~/.ssh/id_rsa` を読む
- ブラウザの cookie file を盗む
- `cat /etc/passwd` する
- ファイルを暗号化して身代金を要求する（ransomware）
- 等々何でもできる

Cowork の "sandbox" は **Bash tool 経由の VM 内 bash にのみ適用される**。hook は外側で動く。

### 実用上の含意

- Cowork = 安全な sandboxed env、というイメージで使われがちだが、**plugin の hook script は host を完全に触れる**
- Plugin を install する前に、hook script の内容を必ず読む文化を作る
- Plugin 配布時は hook script の挙動を docs に明示し、機密 file へのアクセスは最小限に絞る
- code review 時は `hooks/*.sh` を `skills/**/*` よりも厳しく見る

## 2.14 cross-chat 隔離（§1.x には無い Cowork 固有）

Cowork は per-user で 1 つの VM を長期共有しており、chat ごとに Linux user account を切って隔離している。

### 実装例：隔離の確認

```markdown
# in chat A の skill body
​```bash
echo "WHO_AM_I=$(whoami); CWD=$PWD"
ls -la /sessions/ | head -20
​```
```

出力：

```
WHO_AM_I=modest-intelligent-lamport
CWD=/sessions/modest-intelligent-lamport

drwxr-x---   4 modest-intelligent-lamport modest-intelligent-lamport ... modest-intelligent-lamport  ← 自分のもの
drwxr-x---   4 nobody                     nogroup                    ... bold-epic-hamilton          ← 別 chat
drwxr-x---   4 nobody                     nogroup                    ... cli-00f8f26c                ← CLI session の痕跡
... (175 dir)
```

→ 自セッション以外は所有者が `nobody:nogroup`、modeは `drwxr-x---`。他人として cd / cat 不可。

```bash
$ cd /sessions/bold-epic-hamilton
bash: cd: /sessions/bold-epic-hamilton: Permission denied
```

### Metadata leak の例

`ls /sessions/` 自体は world-readable なので：

```markdown
# 任意の plugin の skill 内で
​```bash
ls /sessions/ | wc -l
ls /sessions/ | head -5
​```
```

→ どの plugin からも「このユーザは過去 3 ヶ月で 175 chat 使った」「最新の 5 chat の codename」が分かる。**データ漏洩ではないがメタデータ漏洩**。

### 実用上の含意

- Plugin で「他の chat の存在を知る」「過去の chat 数を数える」等は実装可能（メタデータレベル）
- ただしファイル中身は読めないので、データ漏洩の経路にはなりにくい
- 「Cowork = 完全な per-chat VM」という素朴な前提は誤り

## 2.15 接続フォルダ (`request_cowork_directory`) と rm guard

Cowork は default では `outputs/` 以外への書込ができない（plugin dir も `uploads/` も read-only）。`request_cowork_directory` MCP tool を使うと、ユーザに承認 UI を出して任意のホストフォルダを RW で mount できる。

### 実装例：folder 接続フロー

skill body で：

```markdown
# skills/work-on-host-folder/SKILL.md

ユーザのホスト上の特定フォルダで作業します。まず接続を要求してください。

# Claude が判断して MCP tool を呼ぶ：
# tool: request_cowork_directory
# input: {"path": "C:\\Users\\<user>\\Documents"}

# ユーザの Claude Desktop UI に承認 dialog が出る
# ユーザが「許可」を押すと folder が mount される
```

承認後の挙動：

```bash
# 接続フォルダへの書込 (rw mount)
$ echo "test" > C:\Users\<user>\Documents\foo.txt
# → 成功、ホスト側の C:\Users\<user>\Documents\foo.txt にファイルができる

# 読込もできる
$ cat C:\Users\<user>\Documents\foo.txt
test

# 削除は blocked
$ rm C:\Users\<user>\Documents\foo.txt
rm: cannot remove 'C:\Users\<user>\Documents\foo.txt': Operation not permitted
```

### Mount 情報

```bash
$ mount | grep Documents
/mnt/.virtiofs-root/shared/c/Users/<user>/Documents on C:\Users\<user>\Documents type fuse (rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other)
```

→ rw mount、user_id=0 (root)、allow_other。POSIX 的には何でも書ける状態。**ところが rm は別 layer で block されている**。

### 実用上の含意

- Plugin がユーザのホストファイルを誤って削除する事故は Cowork のレイヤで防がれる（reassuring）
- 「一時ファイルを書いて、後で消す」設計は Cowork で動かない。書きっぱなしを前提に
- 一時ファイルを使いたい場合は `outputs/` 配下に書く（chat 終了時に自動クリーンアップされるはず、要検証）

## 2.16 Cowork validator は CLI より圧倒的に厳しい

CLI の `claude plugin validate` で warning のみで通る違反項目を、Cowork は upload 時に hard reject する。

### 判明している reject 対象

| # | 項目 | CLI 挙動 | Cowork 挙動 |
|---|---|---|---|
| 1 | plugin name の kebab-case 違反 | ⚠ warning（Validation passed with warnings） | ❌ hard reject |
| 2 | hook command 内の `${VAR^^}` 等 bash-specific parameter expansion | ✅ install OK（実行時に Bad substitution） | ❌ install reject |
| 3 | YAML single-quoted string の closing quote 漏れ | ✅ forgiving parser が受理 | ❌ strict parser が reject |
| 4 | skill `description:` 内の `${CLAUDE_*}` substitution markers | ✅ | ❌ reject |
| 5 | skill `description:` 内の `<...>` angle brackets | ✅ | ❌ reject |
| 6 | `UserPromptExpansion` event entry | ✅ | ❌ reject |
| 7 | skill body / frontmatter command content の累積 threshold | ✅ | ❌（具体閾値未特定） |

すべて **`Plugin validation failed`** の generic メッセージで返ってくる。理由表示なし。

### 実装例：Cowork で reject される plugin の例

**`plugin.json`（NG: 大文字混入）：**

```json
{ "name": "My-Plugin", ... }
```

→ Cowork upload で `Plugin validation failed`。CLI なら：

```
⚠ Plugin name "My-Plugin" is not kebab-case. Claude Code accepts it,
  but the Claude.ai marketplace sync requires kebab-case.
Validation passed with warnings
```

**`hooks/hooks.json`（NG: bash-specific expansion）：**

```json
{
  "command": "echo PWD_UPPER=${PWD^^}"
}
```

→ Cowork install で reject。

**`skills/foo/SKILL.md`（NG: description に `${CLAUDE_*}` トークン）：**

```markdown
---
description: "Mounts to ${CLAUDE_SKILL_DIR} read-only"
---
```

→ Cowork install で reject。

**修正方法：** `${...}` や `<...>` を避けて bare token で書く：

```markdown
---
description: "Mounts to CLAUDE_SKILL_DIR read-only"
---
```

### Cowork 対応 plugin チェックスクリプト例

CLI からは検知できないので、CI に Cowork 実機 upload テストを組み込む必要がある。最低限の lint：

```sh
#!/bin/sh
# scripts/cowork-precheck.sh
# 不完全だが、明らかな違反を catch する

PLUGIN_DIR="$1"

# 1. plugin name kebab-case
name=$(jq -r .name "$PLUGIN_DIR/.claude-plugin/plugin.json")
echo "$name" | grep -qE '^[a-z][a-z0-9-]*$' || {
  echo "ERROR: plugin name '$name' is not kebab-case"; exit 1
}

# 2. hook command bash-specific syntax
grep -rE '\$\{[A-Z_]+\^\^?\}|\$\{[A-Z_]+,,?\}' "$PLUGIN_DIR/hooks/" && {
  echo "ERROR: bash-specific parameter expansion (\${VAR^^} etc.) in hooks"; exit 1
}

# 3. description field の ${CLAUDE_*} と <...> markers
find "$PLUGIN_DIR/skills" -name 'SKILL.md' | while read f; do
  desc=$(awk '/^---$/,/^---$/' "$f" | grep '^description:')
  echo "$desc" | grep -qE '\$\{CLAUDE_[A-Z_]+\}|<[a-z]+>' && {
    echo "ERROR: skill description contains \${CLAUDE_*} or <...> in $f"; exit 1
  }
done

# 4. UserPromptExpansion event
grep -l '"UserPromptExpansion"' "$PLUGIN_DIR/hooks/hooks.json" 2>/dev/null && {
  echo "ERROR: UserPromptExpansion event not supported on Cowork"; exit 1
}

echo "Pre-check passed (note: this doesn't catch the content threshold)"
```

### 実用上の対策

- 配布前に **Cowork 実機 upload テスト**を必ず通す
- CI で `claude plugin validate` の warning も failure 扱いする
- description field では `${...}` や `<...>` のような構文を**避け、bare token で書く**
- 名前は全部小文字 + ハイフンに

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
| `PreToolUse:Bash` block | plugin-level なら Cowork でも効く（inline 実装・`${CLAUDE_PLUGIN_ROOT}` 外部スクリプト/redirect 不可）。frontmatter PreToolUse:Skill は Cowork で効かない |
| `UserPromptExpansion` event | Cowork validator が reject するので、Cowork 配布版では hooks.json から除外 |
| 削除操作 | 接続フォルダでも `rm` は不可。一時ファイルは作らない |
| userConfig | Cowork では UI が無い。CLI のみで使う設定として割り切る |
| 実機テスト | CLI で `claude plugin validate` PASS + Cowork で zip upload PASS + 実機 invoke で挙動確認、の 3 段 |
| hook script のレビュー | plugin-level hook は host machine への完全アクセスを持つ（Cowork でも）。code review を厳しくする |

---

# 付録 B：OpenTelemetry ベースの skill 発火追跡

§1.9 で「skill が slash 経由か自然言語経由かで発火する hook が違う」点を示した。**hook ベースで両経路をカバーする plugin を書くのは可能だが、可観測性（telemetry / 監査）の用途には Claude Code が emit する OpenTelemetry event を使う方が圧倒的に綺麗**。本付録は v2.1.150 時点の Grafana Loki 実機調査結果に基づく。

## B.1 hook ベース追跡だと何が困るのか

§1.9 の表を「telemetry に使えるか」の観点で読み直すと：

| 観測したい状況 | 自然言語経由 | slash 経由 | nested skill chain |
|---|:---:|:---:|:---:|
| `PreToolUse:Skill` で skill 起動を catch | ✅ | ❌ | ✅（子 skill のみ） |
| `UserPromptExpansion` で slash を catch | ❌ | ✅（CLI のみ） | ❌ |
| `UserPromptSubmit` で根プロンプトを catch | ✅ | ✅ | ✅（根のみ） |

要点：
- 単一の hook では全経路を carry できない
- 両方仕込んでも、Cowork では `UserPromptExpansion` が validator reject される
- nested-skill chain（skill が別 skill を呼ぶ）の追跡は hook 側では結局困難
- hook は **plugin-local**。複数 plugin / マシン横断で集計するなら、ログ集約パイプラインを自前で立てる必要あり

## B.2 Claude Code が emit する OTel event 一覧

`service_name=claude-code` の Loki ストリームに 11 種の `event_name` が観測された：

| event_name | 内容 |
|---|---|
| `user_prompt` | ユーザがプロンプトを送った |
| `api_request` | Anthropic API へのリクエスト送信 |
| `tool_decision` | tool 実行を decide（permission UI 含む） |
| `tool_result` | tool 結果が戻った |
| `hook_registered` | hook 登録（skill frontmatter hook の lifecycle 観測可） |
| `hook_execution_start` / `hook_execution_complete` | hook 実行の begin/end |
| `mcp_server_connection` | MCP server への接続 |
| `plugin_loaded` | plugin が読み込まれた |
| `permission_mode_changed` | `defaultMode` 等の変化 |
| `subagent_completed` | sub-agent（Agent tool）の完了 |
| **`skill_activated`** | **本付録の主題：skill が起動した** |

`service_name=claude-code-desktop` も `skill_activated` を emit する。  
**`service_name=cowork` も emit する**（v2.1.149 in host-adjacent VM で確認）。3 種類すべての `invocation_trigger` 値（`user-slash` / `claude-proactive` / `nested-skill`）が Cowork でも観測される。

> ※ 初期調査では Cowork に skill_activated 不在と誤判定したが、これは event_name の distinct を limit=1000 のサンプルで取った際、頻度の低い skill_activated が切られて見えなかっただけだった。`|~ "skill_activated"` の line filter で全期間スキャンすると検出できる。Appendix の他のセクション（§B.7、§B.8）もこの訂正後の前提で読むこと。

Cowork 経由の event は **CLI 版とほぼ同じ shape だが、固有のフィールド値**がいくつかある：

| field | CLI 版 (`claude-code`) | Cowork 版 (`cowork`) |
|---|---|---|
| `marketplace_name` | 通常 marketplace 名 | zip upload 経由は `inline`、marketplace 経由 install ならその marketplace 名（Cowork も marketplace 経路自体は対応） |
| `terminal_type` | `Apple_Terminal`, `iTerm`, 等 | **`non-interactive` 固定** |
| `service_version` | `2.1.150` 等 Claude Code 版 | **`1.8555.x` 等 Claude Desktop 版** |
| `scope_version` | 同上 | **`2.1.149` 等 Claude Code core 版**（service と別系統） |
| `workspace_host_paths` | 通常未設定 | 接続フォルダの host path 配列（PII 注意） |
| `prompt`（user_prompt event） | redacted | **平文で記録**（PII / 機密含む可能性） |

## B.3 `claude_code.skill_activated` の構造

実観測した属性フィールド：

| field | 例 | 用途 |
|---|---|---|
| `event_name` | `skill_activated` 固定 | クエリの軸 |
| `invocation_trigger` | `user-slash` / `claude-proactive` / `nested-skill` | **§B.4 の経路区別キー** |
| `skill_name` | `waggle:bootstrap-session` | `<plugin>:<skill>` or `<skill>` |
| `skill_source` | `plugin` / `builtin` / `bundled` / `projectSettings` / `userSettings` | 出処の分類 |
| `plugin_name` | `waggle` | plugin 由来時のみ |
| `marketplace_name` | `waggle` | 同上 |
| `prompt_id` | UUID | **§B.5 の chain 復元キー** |
| `session_id` | UUID | chat session |
| `service_version` | `2.1.150` | バージョン横断分析用 |
| `user_email` / `user_account_id` | identity | 個人特定可能、PII 注意 |
| `terminal_type`, `os_type`, `host_arch` | `Apple_Terminal` / `darwin` / `arm64` 等 | env breakdown |

## B.4 `invocation_trigger` の 3 値と対応する起動経路

| 値 | 起動経路 | §1.9 の対応 hook |
|---|---|---|
| `user-slash` | ユーザが `/<plugin>:<skill>` を入力 | UserPromptExpansion（CLI のみ） |
| `claude-proactive` | Claude が自然言語プロンプトから自発的に発火 | PreToolUse:Skill |
| `nested-skill` | 別 skill が `Skill` tool を呼んで chain した | PreToolUse:Skill（子 skill） |

サンプル：

```jsonc
// user-slash の例
{
  "event_name": "skill_activated",
  "invocation_trigger": "user-slash",
  "skill_name": "tech-blog-generator",
  "skill_source": "projectSettings",
  "plugin_name": null,             // project-local skill なので plugin 不在
  "prompt_id": "3e472fd7-…",
  "session_id": "a219c192-…"
}

// claude-proactive の例
{
  "event_name": "skill_activated",
  "invocation_trigger": "claude-proactive",
  "skill_name": "log-session-summary",
  "skill_source": "userSettings",
  "plugin_name": null,
  "prompt_id": "6e761fef-…",
  "session_id": "7c92f381-…"
}

// nested-skill の例
{
  "event_name": "skill_activated",
  "invocation_trigger": "nested-skill",
  "skill_name": "waggle-notion:notion-provider",
  "skill_source": "plugin",
  "plugin_name": "waggle-notion",
  "marketplace_name": "waggle",
  "prompt_id": "8013a35a-…",
  "session_id": "dfe0517c-…"
}
```

## B.5 `prompt_id` による skill chain 復元

**同じユーザプロンプトから派生した全 skill activation は同じ `prompt_id` を共有する**。これにより hook では複雑だった「chain 全体の起点はどの skill だったか」が単純な GROUP BY 1 本で復元できる。

観測例（実データから抽出、prompt_id = `8013a35a-...`）：

```
2026-05-26T00:27:51.194Z  skill_activated  nested-skill  waggle:managing-tasks
2026-05-26T00:27:54.602Z  skill_activated  nested-skill  waggle:bootstrap-session
2026-05-26T00:27:56.727Z  skill_activated  nested-skill  waggle:detecting-provider
2026-05-26T00:28:07.476Z  skill_activated  nested-skill  waggle-notion:notion-provider
```

→ 同一ユーザプロンプトから 4 つの skill が連鎖発火した chain と分かる。ただし 4 つすべて `nested-skill` なのは、最初の起動経路（user-slash or claude-proactive）の event が別の event_name 下にあるか、または検索 limit でこぼれた可能性あり。**chain root を特定したい場合は、同 `prompt_id` で `user_prompt` event を別途検索**：

```logql
{service_name="claude-code"} |~ "user_prompt"
  | json | prompt_id="8013a35a-..."
```

## B.6 実用的な LogQL クエリ集

### a) 自プラグインの skill activation 集計

```logql
{service_name=~"claude-code(-desktop)?"} |~ "skill_activated"
  | json | plugin_name="waggle"
```

→ panel: skill_name でグループ化して time-series stacked area。

### b) user-slash vs claude-proactive の比率

```logql
sum by (invocation_trigger) (
  count_over_time(
    {service_name=~"claude-code(-desktop)?"} |~ "skill_activated"
      | json | plugin_name="waggle" [1h]
  )
)
```

→ panel: pie chart。「自然発火がほとんど」「slash で叩く文化が定着」等の運用文化が見える。

### c) skill 起動失敗（hook で block された）の検知

`skill_activated` は **block されなかった**起動のみ emit される（hook が PreToolUse:Skill で decision: block を返すと event が出ない）。block 状況を見たい場合は `tool_decision` event 経路：

```logql
{service_name="claude-code"} |~ "tool_decision"
  | json
  | tool_name="Skill"
  | decision="block"
```

### d) chain depth の集計

同一 `prompt_id` 内の `skill_activated` 件数 = chain length。

```logql
sum by (prompt_id) (
  count_over_time(
    {service_name="claude-code"} |~ "skill_activated"
      | json | plugin_name="waggle" [1d]
  )
)
```

→ histogram にすれば「ほとんど chain 1」「ときどき 4 段 nest」等の分布が見える。

### e) skill_source 分布

```logql
sum by (skill_source) (
  count_over_time(
    {service_name="claude-code"} |~ "skill_activated" [1d]
  )
)
```

→ `plugin` vs `userSettings` vs `projectSettings` 等の使われ方比率。

## B.7 service_name × event_name 可視性マトリクス

| service_name | skill_activated | hook 系 | tool 系 | api_request | 注記 |
|---|:---:|:---:|:---:|:---:|---|
| `claude-code` | ✅ | ✅ | ✅ | ✅ | ターミナル CLI 経由 |
| `claude-code-desktop` | ✅ | ✅ | ✅ | ✅ | Claude Desktop CLI 経由（`api_error` `api_retries_exhausted` もここのみ。user_prompt の `prompt` は redact 済） |
| `cowork` | ✅ | ✅ | ✅ | ✅ | Cowork VM 側。3 種の `invocation_trigger` すべて観測可能。`compaction` `internal_error` がここのみ。user_prompt の `prompt` は **redact なし生平文**で保存される（PII 注意） |

## B.8 Cowork での skill 追跡レシピ

Cowork は `service_name=cowork` ストリームに `skill_activated` を吐く。CLI 版とほぼ同等の精度で追跡可能。具体クエリは以下。

### a) 自プラグインの全 activation（両経路 + nested 含む）

```logql
{service_name="cowork"} |~ "skill_activated"
  | json | plugin_name="<your-plugin>"
```

`marketplace_name` での絞り込みは Cowork で zip upload された plugin だと `inline` になる（marketplace 経由 install なら実 marketplace 名）。zip と marketplace を併用する team は `plugin_name` で絞るのが安全。

### b) user-slash 経路のみ（ユーザが `/<plugin>:<skill>` を入力した分）

```logql
{service_name="cowork"} |~ "skill_activated"
  | json | invocation_trigger="user-slash" | plugin_name="<your-plugin>"
```

→ 「ユーザが意識的に呼び出した skill」の集計。チーム文化計測に有用。

### c) claude-proactive 経路のみ（自然言語から Claude が自動発火した分）

```logql
{service_name="cowork"} |~ "skill_activated"
  | json | invocation_trigger="claude-proactive" | plugin_name="<your-plugin>"
```

→ 「skill description が機能して Claude が選んでくれた」割合の計測。description チューニングの効果測定に。

### d) nested chain（別 skill から呼ばれた depth 集計）

```logql
sum by (prompt_id) (
  count_over_time(
    {service_name="cowork"} |~ "skill_activated"
      | json | plugin_name="<your-plugin>" [1d]
  )
)
```

→ histogram で chain depth 分布。

### e) tool_decision / tool_result の `tool_name=Skill` は claude-proactive と nested-skill のみ

§1.9 で確認した通り、**slash 経由は Skill tool を経由しない**。Loki でも実機確認済（同一 prompt_id 内の event 数）：

| 経路 | tool_name=Skill event 数 |
|---|:---:|
| user-slash | **0** |
| claude-proactive | 2（decision + result） |
| nested-skill | 2 × chain 段数 |

つまり `tool_decision` / `tool_result` の `tool_name=Skill` を skill_activated の **フォールバックとして使うのは誤り**（slash 経由が抜ける）。次の用途には有用：

- **skill 実行の latency 計測**：`tool_decision` (start) → `tool_result` (end) の時間差。skill_activated event 単独では持っていない情報
- **skill 起動の accept/reject 判定**：`tool_decision.decision` に `accept` / `reject` 等が入る
- **claude-proactive / nested-skill 限定の精緻なメタデータ**：`tool_input` には `{"skill":"<name>"}`、`tool_parameters` には `{"skill_name":"<name>"}` が入る

「skill 起動回数を全経路で集計したい」用途では **skill_activated を使う**（user-slash も含めて全経路カバー）。

### f) ユーザが実際に入力した slash command 文字列

```logql
{service_name="cowork"} |~ "user_prompt"
  | json | prompt=~"^/[a-z].*"
```

→ `/waggle:planning-tasks ...` のように引数つきの slash 入力の生文字列が見える。dashboard の権限は team-only に絞る（PII 含み得る）。

### g) Cowork 経由 vs CLI 経由の比率

```logql
sum by (service_name) (
  count_over_time(
    {service_name=~"claude-code|claude-code-desktop|cowork"} |~ "skill_activated"
      | json | plugin_name="<your-plugin>" [7d]
  )
)
```

→ Cowork 利用が増えているか、ターミナル CLI が主流か、Desktop CLI が主流か、を 1 枚で可視化。

## B.9 caveat と運用上の注意

- **PII 含有**：`user_email`、`user_account_id`、`session_id`、プロンプト本文の prompt_id 紐付けがあるので、ダッシュボード公開範囲は team 内に限定する
- **schema drift**：observed `service_version` が `2.1.137` と `2.1.150` で混在していた。フィールド名・取りうる値はマイナーバージョン間で増える可能性あり。alert は緩めに書く
- **block された skill は記録されない**：hook で block された skill activation は `skill_activated` event を残さない。block 統計が必要なら `tool_decision` event を見る
- **Cowork ↔ CLI のフィールド非対称**：§B.2 の表の通り Cowork は zip upload なら `marketplace_name=inline`、marketplace 経由 install なら実 marketplace 名と二系統に分かれる。`terminal_type=non-interactive` は Cowork で常に固定。`marketplace_name` で plugin 由来を絞ると zip 経路を取りこぼすので、`plugin_name` で絞るのが安全
- **Cowork の user_prompt が PII を保持**：`prompt` フィールドが redact なしで保存される。slash command の引数や自然言語でのユーザ依頼が生のまま入るので、ダッシュボードの permission は厳しく
- **telemetry の有効化**：OTel exporter は `CLAUDE_CODE_ENABLE_TELEMETRY=1` および OTLP endpoint 設定（あるいは Anthropic 提供の Grafana Cloud 共有設定）が必要。CLI の `hook_registered` event 群を確認すれば自プラグインの hook が import されたか telemetry で見えるかが分かる
- **検証手段**：本付録の値は 2026-05-26 時点の Grafana Loki 実機サンプルから抽出。再現は `https://logs-prod-030.grafana.net/loki/api/v1/query_range` に basic auth で接続して `{service_name="claude-code"} |~ "skill_activated"` を投げれば誰でもできる

---

# 参考文献

- 検証結果の生データ：`findings/v2.1.146/observations.md`（1300 行超）
- 集計レポート：`findings/v2.1.146/report.md`
- 元になった研究記録（v2.1.118-119 時点、private）
- 検証プラグイン本体：`verifier/`
- Cowork 専用検証 zip：`findings/v2.1.148/verifier-cowork-*.zip`
- OTel 実機観測：Grafana Loki, 2026-05-26 時点
