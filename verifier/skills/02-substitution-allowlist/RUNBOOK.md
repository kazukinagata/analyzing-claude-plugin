# RUNBOOK: 02-substitution-allowlist

## 検証内容（§1.2 / §3.2）

skill body の `${VAR}` 置換と、skill frontmatter で `${CLAUDE_PLUGIN_DATA}` を参照した際の validator block / `${user_config.KEY}` の `/bin/sh` Bad substitution。

## 事前準備

1. 00-canary が PASS していること
2. `./scripts/install-marketplace.sh` を一度実行して `findings/v.../install.log` を生成（verifier-violator の install エラーを観察するため）
3. `verifier-violator` 配下に以下が用意されていること（このリポジトリ scaffolding で作成済）：
   - `verifier-violator/skills/02b-data-in-frontmatter/SKILL.md` — frontmatter hook に `${CLAUDE_PLUGIN_DATA}` を書いて validator block を狙う
   - `verifier-violator/skills/02c-userconfig-in-frontmatter/SKILL.md` — frontmatter hook に `${user_config.hello_message}` を書いて `Bad substitution` を狙う

## 手順

```sh
cd /path/to/analyzing-claude-plugin
. scripts/_env.sh
./scripts/install-marketplace.sh   # ← まだ未実行ならここで
# 別 terminal:
claude --plugin-dir ./verifier --plugin-dir ./verifier-violator
```

プロンプトで：
```
/verifier:02-substitution-allowlist
```

続けて 02c の Bad substitution を観察するには、同セッションで自然文で「`02c-userconfig-in-frontmatter` skill を起動して、その後で何かしらの Bash 実行をしてみてください」と頼みます。`/bin/sh: ... Bad substitution` のエラーが Claude の出力に出るはずです。

完了して exit、`./scripts/assert.sh 02`。

## subclaim

1. **skill body の置換**：SUBST_ROOT / SUBST_DATA / SUBST_SKILL_DIR / SUBST_SESSION_ID が **literal でない**（絶対 path や UUID に展開されている）
2. **PROJECT_DIR は literal**：SUBST_PROJECT_DIR が `${CLAUDE_PROJECT_DIR}` のまま残る
3. **validator block**：install.log に `plugin-only` または `CLAUDE_PLUGIN_DATA` または `skill hooks` のいずれかの単語が出現（loose match）
4. **Bad substitution**：install.log または別経路の log に `Bad substitution` が出現

## 想定 verdict

- 全 subclaim 一致 → **PASS**
- どこか欠ける → **PARTIAL** or **FAIL**
