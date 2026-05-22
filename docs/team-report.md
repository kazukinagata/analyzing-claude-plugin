# Claude Code Plugin 作成ガイド — CLI と Cowork の挙動差分まとめ

## この文書の目的

Claude Code（Anthropic 公式 CLI / Claude Desktop アプリ）には plugin 機構があり、プロジェクト固有の skill（指示書）や hook（バックグラウンド処理）を定義できる。ところが公式 docs には書かれていない仕様や、ドキュメントと挙動が矛盾する箇所が多数あり、plugin を実装すると「動くはずなのに動かない」「CLI では動くのに Cowork（Claude Desktop の VM 実行モード）では動かない」といった事象に頻繁にぶつかる。

本資料は、それらの落とし穴を実機検証で洗い出した結果をチーム共有用にまとめたもの。検証対象は **Claude Code v2.1.146（CLI 側）+ v2.1.146-148（Cowork 側）**、2026 年 5 月時点。

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
| **Cowork** | Claude Desktop アプリ（Windows）で動く VM 実行モード。本資料の検証で **実体は host-adjacent な VM + virtio-fs**（つまり「クラウド」ではなくユーザ機の隣接 VM）であることが判明している |

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
| `CLAUDE_PROJECT_DIR` | ✅ | 未確認 | ❌ |
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
| `${user_config.KEY}` | ✅ | ❌ literal で `/bin/sh` に渡る → `Bad substitution` エラー | 未検証 |
| `${CLAUDE_SKILL_DIR}` | ❌ | 未検証 | ✅（SKILL.md の dirname） |
| `${CLAUDE_SESSION_ID}` | 未検証 | 未検証 | ✅（session UUID） |
| `${CLAUDE_PROJECT_DIR}` | ✅ | 未検証 | ❌ literal のまま |

skill frontmatter hook に `${CLAUDE_PLUGIN_DATA}` を書くと、install 時の validator が以下メッセージで reject する：

```
Hook command references ${CLAUDE_PLUGIN_DATA} but only ${CLAUDE_PLUGIN_ROOT}
is available for skill hooks (${CLAUDE_PLUGIN_DATA} is plugin-only).
```

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
echo "project dir (literal): ${CLAUDE_PROJECT_DIR}"
​```
```

→ Claude が skill を invoke する時に Claude Code 本体が置換するので、Claude に渡る context は：

```
echo "plugin install path: /home/user/.claude/plugins/cache/<...>/my-plugin"
echo "this skill dir: /home/user/.claude/plugins/cache/<...>/my-plugin/skills/my-skill"
echo "session id: 9307ae27-a40f-44d8-85d9-32838abbd9a1"
echo "project dir (literal): ${CLAUDE_PROJECT_DIR}"  ← これだけ literal で残る
```

### 実用上の対策

- skill frontmatter で userConfig を参照しない（`Bad substitution` で死ぬ）
- `${CLAUDE_PROJECT_DIR}` は skill body 内では literal のまま残る。実体を欲しいなら hook 経由で書き出すか、bash で `$(pwd)` 等を使う
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

### 実用上の対策

- 機密値を扱う処理は **plugin-level hook の範囲に閉じ込める**（skill frontmatter / Bash tool には env が伝わらないのでそもそも漏らせない）
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
# これは動かない：${user_config.api_secret} は skill body では置換されない
# 仮に置換されたとしても、Bash tool の env には CLAUDE_PLUGIN_OPTION_API_SECRET が来ない
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

第 2 章の各節は、Cowork の architecture を理解していないと「なぜそうなる」が腑に落ちない。検証で判明した model：

### 構造図

```
┌──────────────────────────────────────────────────────────────┐
│ ユーザの Windows machine (例: LAPTOP-BKGB6100)                │
│                                                              │
│  ┌────────────────────────────────────────────┐              │
│  │ Claude Desktop (Windows process)            │              │
│  │   + plugin-level hook 実行 (WSL 経由)        │ ← ① hook    │
│  │     hostname=LAPTOP-BKGB6100                │              │
│  │     PATH=/usr/bin:/mnt/c/Users/knaga/...    │              │
│  │     /sessions/ は見えない                    │              │
│  └─────────────┬──────────────────────────────┘              │
│                │                                              │
│                │ virtio-fs FUSE mount                          │
│                ↓                                              │
│  ┌────────────────────────────────────────────┐              │
│  │ Cowork VM (host-adjacent, KVM/Hyper-V?)     │              │
│  │   hostname=claude                           │              │
│  │   /sessions/<codename>/                     │              │
│  │     ├─ mnt/.remote-plugins/plugin_<id>/    │              │
│  │     │   (host から ro mount)                │              │
│  │     ├─ mnt/outputs/  (host から rw mount)   │              │
│  │     └─ mnt/uploads/  (host から ro mount)   │              │
│  │   Bash tool (mcp__workspace__bash) 実行     │ ← ③ Bash tool│
│  └────────────────────────────────────────────┘              │
└──────────────────────────────────────────────────────────────┘
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
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/usr/lib/wsl/lib:/mnt/c/Users/knaga/AppData/Local/...
```

→ **hook は user's Windows machine の WSL 上で実行されている**。`/mnt/c/Users/knaga/...` という WSL mount path が PATH に含まれている。

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
/mnt/.virtiofs-root/shared/c/Users/knaga/.../outputs on .../outputs type fuse (rw,...)
/mnt/.virtiofs-root/shared/c/Users/knaga/.../uploads on .../uploads type fuse (ro,...)
/mnt/.virtiofs-root/shared/c/Users/knaga/.../rpm/plugin_<id> on /sessions/.../mnt/.remote-plugins/plugin_<id> type fuse (ro,...)
```

→ `/sessions/<codename>/mnt/` 配下が **virtio-fs で host filesystem を bind mount** していることが確定。`/mnt/.virtiofs-root/shared/c/Users/knaga/...` が host の `C:\Users\knaga\...` の VM 内表現。

### Why this matters

この split で以下の挙動が **自動的に**説明される：
- §2.1 hook env から CLAUDE_PLUGIN_* が消えた → host 側の env を Claude Desktop が export していないだけ
- §2.7 file I/O 不可視 → hook が書く `/tmp/foo.txt` は WSL の /tmp、Bash tool が読む `/tmp/foo.txt` は Cowork VM の /tmp、別 namespace
- §2.8 path の Windows form → skill body の `${CLAUDE_PLUGIN_ROOT}` は Claude Desktop (Windows) が知っている install path に置換
- §2.10 PreToolUse block 不発 → hook の decision が host から VM までネットワーク越しに届かない、または VM 側で無視している
- §2.13 trust 境界 → plugin-level hook が host machine への完全アクセスを持つ（!）

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

- Cowork で plugin-level hook から plugin install dir を参照したいなら **`${CLAUDE_PLUGIN_ROOT}` 置換**を使う必要あり（env var 経由はもう動かない）
- ただし後述 2.2 の通り、Cowork では `${VAR}` 置換も top-level command では機能しない。**結局 hook 内で plugin path を取得する手段がほぼ消失している**
- CLI/Cowork 両対応の plugin は `bash -c` + hostname 判定で動作を分岐する設計が必要

## 2.2 `${VAR}` 置換と shell expansion（§1.2 / §1.3 の Cowork 版）

最大の落とし穴。Cowork の plugin-level hook command は **二段階の実行モード**に分かれている：

| hook command の書き方 | 実行モード | `$VAR` / `${VAR}` の扱い |
|---|---|---|
| **top-level** `echo X` | literal text emission（shell プロセス起動なし）| `$VAR` も `${VAR}` も**完全に展開されない、literal 文字列のまま** |
| **`bash -c "..."` で wrap** | 実 bash subprocess 起動 | フル POSIX 展開（`$VAR` も `${VAR}` も期待通り） |

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
- top-level: shell process が起動されない → 何も展開されない
- `bash -c "..."`: 実 bash が起動 → POSIX 通りに展開

### 実装例：${CLAUDE_PLUGIN_ROOT} を hook で使いたい場合

**NG（top-level）：**

```json
{
  "command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/my-script.sh\""
}
```

→ Cowork では literal `${CLAUDE_PLUGIN_ROOT}/hooks/my-script.sh` が「実行」されようとして失敗（そんなパスのファイルは無いので）。

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

## 2.3 hook 実行シェルとシェル機能（§1.3 の Cowork 版）

CLI の hook 実行シェルは `/bin/sh`（dash）だった。Cowork は前述の通り「top-level は shell プロセスなし、`bash -c` で wrap した時だけ実 bash」という二段階モデル。

### 実装例

**Cowork の top-level で `[[ ]]` を書くと？**

```json
{ "command": "[[ -d /foo ]] && echo yes" }
```

→ top-level は literal emission なので「`[[ -d /foo ]] && echo yes`」がそのまま context に注入される。shell が起動されていないのでエラーすら出ない。意図と全然違う動作。

**Cowork で `bash -c` 経由なら `[[ ]]` も使える：**

```json
{ "command": "bash -c '[[ -d /foo ]] && echo yes'" }
```

→ 実 bash が `bash -c` で起動するので bash 構文が使える。

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

### 実用上の対策

- Cowork では `${user_config.KEY}` を hook command に書かない
- 必要な値は skill body で Claude に教えさせる経路を取る

## 2.6 marketplace cache（§1.6 の Cowork 版）

Cowork には marketplace 概念そのものが無い。zip を Claude Desktop UI に upload する経路のみ。ローカル開発フローは「zip を再生成して再 upload」のループになる。

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
echo "BODY_SUBST_ROOT=C:/Users/knaga/AppData/Roaming/Claude/local-agent-mode-sessions/<sess-uuid>/<inner-uuid>/rpm/plugin_<id>"
echo "BODY_SUBST_DATA=C:/Users/knaga/AppData/Roaming/Claude/.../local_<sess-uuid>/.claude/plugins/data/<plugin-name>-inline"
echo "BODY_SUBST_SKILL_DIR=C:/Users/knaga/AppData/Roaming/Claude/.../rpm/plugin_<id>/skills/path-readback"
```

これを Bash tool（cloud VM 側で動く）で実行すると：

```
BODY_SUBST_ROOT=C:/Users/knaga/...
BODY_SUBST_DATA=C:/Users/knaga/...
BODY_SUBST_SKILL_DIR=C:/Users/knaga/...
```

→ **Windows パス文字列がそのまま echo されるだけ**。これを `bash` に渡すと cloud VM の filesystem には存在しないので失敗する：

```bash
$ bash "${CLAUDE_PLUGIN_ROOT}/scripts/say-hi.sh"
bash: C:/Users/knaga/.../scripts/say-hi.sh: No such file or directory
```

### Cowork で bundled script を実行する正しい方法

`find /sessions` で cloud VM 側の mount path を localize：

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
| bundled script を Bash tool から起動 | `${CLAUDE_PLUGIN_ROOT}` は使わず、`find /sessions -path '*/skills/<name>' -type d` で cloud VM 側の mount path を localize してから cd + 相対 path |
| `${CLAUDE_PLUGIN_DATA}` への永続化 | できない。§2.8 参照 |
| Windows path を bash で `mkdir -p` | **危険**：bash は `:` を path separator として解釈しないので、`mkdir -p "C:/foo"` は **`$PWD/C:/foo` というゴミディレクトリを silent に作る**。必ずガードを入れる：`[[ "$path" =~ ^[A-Z]: ]] && return 1` |

## 2.8 hook と Bash tool は完全に別の filesystem（§1.7 の派生）

Cowork architecture が原因で、**plugin-level hook が書いたファイルは Bash tool 側からは見えない**。

理由：
- plugin-level hook はホスト Windows / WSL Ubuntu で実行される
- Bash tool は cloud VM で実行される
- 両者は別の filesystem namespace

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

→ hook は **host machine (WSL Ubuntu)** で実行されるので `/tmp/canary.txt` が host の `/tmp` に書かれる。

**Bash tool 内で読もうとする：**

```markdown
# skills/read-canary/SKILL.md

​```bash
cat /tmp/canary.txt
​```
```

→ Bash tool は **Cowork VM** で実行されるので VM の `/tmp` を見る。host の `/tmp/canary.txt` は見えない。

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

ただしこれは **session-scope（同一 chat 内）でしか有効ではなく**、永続化にも使えない。新規 chat では SessionStart hook が再度発火して別の context として再注入される。

### 実用上の含意

- Cowork で「hook が状態を持って、後で skill が読む」というよくあるパターンは動かない
- 状態を渡す手段は stdout → additionalContext のみ
- 永続化が必要な plugin は Cowork で別設計が必要（outputs/ にユーザの目に見える形で書く等）

## 2.9 skill frontmatter hook の登録タイミング（§1.8 の Cowork 版）

CLI では「一度 invoke した skill の frontmatter hook は `claude` プロセス終了まで生存」だった。Cowork では：

- skill frontmatter hook は **1 プロンプト内のみ有効**（VM suspend/resume で reset される）
- 同一 chat 内で window を非アクティブにして 3 分以上放置 → 戻ると skill を再 invoke するまで frontmatter hook 不発

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

- Cowork で長期的な guard を仕掛けたいなら frontmatter hook ではなく plugin-level hook を使う（ただし §2.10 の通り plugin-level PreToolUse block は無効化されている）
- 「user の bash 試行を guard したい」系の plugin は Cowork で実質機能不能
- 諦めて skill body の冒頭でチェックを書く、または各 skill に inline で同じガードを置く

## 2.10 plugin-level PreToolUse block の無効化

CLI では plugin-level `PreToolUse` hook で `{"decision":"block","reason":"..."}` を返せば Bash tool 等を止められた。**Cowork ではこれが完全に死亡**。

### 実装例

```json
// hooks/hooks.json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "mcp__workspace__bash",
        "hooks": [
          { "type": "command",
            "command": "echo '{\"decision\":\"block\",\"reason\":\"plugin-level block\"}'" }
        ]
      }
    ]
  }
}
```

CLI（matcher を `"Bash"` にした場合）：
- ユーザが Claude に「`ls` してください」と頼む
- Claude が Bash tool を呼ぶ
- PreToolUse hook が block decision を返す
- Claude に「blocked」が伝わって ls しない ✅

Cowork：
- 同じ操作
- PreToolUse hook は呼ばれている形跡がある（log を取ると確認できる）
- でも block decision が無視される
- `ls` が普通に実行される ❌

### 検証手順

matcher を `Bash` / `Skill` / `.*` / `mcp__workspace__bash` の 4 通りすべて試した。JSON `decision: block` でも `exit 2` でも block されず、skill body の `echo TEST_BASH_OK_MARKER` が普通に実行された。

### 実用上の含意

- 「危険な bash コマンドを plugin が事前に止める」系の guard は Cowork で動かない
- skill frontmatter の `PreToolUse:Skill` による skill-to-skill block は Cowork でも生存（§1.11 ベースで動く）
- ユーザ自身に permission UI で OK / NG を判断させる Cowork の仕組みを信頼する設計に切り替える

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
| skill body の bash | cloud VM (sandbox) | sandbox 内に閉じ込められる |
| plugin-level hook | **ホスト machine (WSL Ubuntu)** | **ホストへの完全アクセスを持つ**（!!） |
| Bash tool subprocess | cloud VM (sandbox) | sandbox 内 |

### 実装例：plugin-level hook が host にアクセスできる証拠

```json
// hooks/hooks.json — Cowork で動く
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command",
            "command": "bash -c 'echo HOST_FILES=$(ls /mnt/c/Users/knaga/Documents 2>&1 | head -5)'" }
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

→ plugin-level hook は **ユーザの Documents フォルダの中身を完全に読める**。これは sandboxed VM ではなく、host machine で実行されているから。

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
# input: {"path": "C:\\Users\\knaga\\Documents"}

# ユーザの Claude Desktop UI に承認 dialog が出る
# ユーザが「許可」を押すと folder が mount される
```

承認後の挙動：

```bash
# 接続フォルダへの書込 (rw mount)
$ echo "test" > C:\Users\knaga\Documents\foo.txt
# → 成功、ホスト側の C:\Users\knaga\Documents\foo.txt にファイルができる

# 読込もできる
$ cat C:\Users\knaga\Documents\foo.txt
test

# 削除は blocked
$ rm C:\Users\knaga\Documents\foo.txt
rm: cannot remove 'C:\Users\knaga\Documents\foo.txt': Operation not permitted
```

### Mount 情報

```bash
$ mount | grep Documents
/mnt/.virtiofs-root/shared/c/Users/knaga/Documents on C:\Users\knaga\Documents type fuse (rw,nosuid,nodev,relatime,user_id=0,group_id=0,default_permissions,allow_other)
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
| `PreToolUse:Bash` block | Cowork では plugin-level の block は無効。skill frontmatter で代替するか諦める |
| `UserPromptExpansion` event | Cowork validator が reject するので、Cowork 配布版では hooks.json から除外 |
| 削除操作 | 接続フォルダでも `rm` は不可。一時ファイルは作らない |
| userConfig | Cowork では UI が無い。CLI のみで使う設定として割り切る |
| 実機テスト | CLI で `claude plugin validate` PASS + Cowork で zip upload PASS + 実機 invoke で挙動確認、の 3 段 |
| hook script のレビュー | plugin-level hook は host machine への完全アクセスを持つ（Cowork でも）。code review を厳しくする |

---

# 参考文献

- 検証結果の生データ：`findings/v2.1.146/observations.md`（1300 行超）
- 集計レポート：`findings/v2.1.146/report.md`
- 元になった研究記録（v2.1.118-119 時点）：`/home/kazukinagata/projects/sandbox/research.md`
- 検証プラグイン本体：`verifier/`
- Cowork 専用検証 zip：`findings/v2.1.148/verifier-cowork-*.zip`
