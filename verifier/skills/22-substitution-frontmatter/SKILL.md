---
name: 22-substitution-frontmatter
description: Single-quote isolation probe to fill team-report §1.2 unverified cells. Tests Claude Code pre-substitution in plugin-level hook + skill frontmatter hook + skill body for SESSION_ID, PROJECT_DIR, SKILL_DIR, and user_config.KEY.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: '"${CLAUDE_PLUGIN_ROOT}/hooks/subst-probe.sh" fm SESSION_ID ''${CLAUDE_SESSION_ID}'''
        - type: command
          command: '"${CLAUDE_PLUGIN_ROOT}/hooks/subst-probe.sh" fm PROJECT_DIR ''${CLAUDE_PROJECT_DIR}'''
        - type: command
          command: '"${CLAUDE_PLUGIN_ROOT}/hooks/subst-probe.sh" fm SKILL_DIR ''${CLAUDE_SKILL_DIR}'''
---

# 22-substitution-frontmatter

§1.2 マトリクスの未検証セルを single-quote isolation で観測する probe。

## 観測の仕組み

`'${CLAUDE_SESSION_ID}'` のように **single-quote 内**に `${VAR}` を書くと：
- 事前置換あり → Claude Code 本体が string を書き換え、shell には実値が渡る → log に実値
- 事前置換なし → string そのまま shell に渡る、single-quote で shell expansion 抑止 → log に literal `${...}`

期待結果（v2.1.146 推測）：

| tier | SESSION_ID | PROJECT_DIR | SKILL_DIR | user_config.KEY |
|---|:---:|:---:|:---:|:---:|
| plugin-level | ? | ✅ | ? | ✅ |
| frontmatter | ? | ? | ? | — |
| body | ✅ | ✅ | ✅ | ? |

## step 1: body tier の事前置換を観測 + 直近 log を表示

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
out_dir="$proj/findings/$ver/probe-22"
mkdir -p "$out_dir"

# body tier — single-quote isolation
echo '[BODY] USER_CONFIG=${user_config.hello_message}' >> "$out_dir/subst.log"
echo '[BODY] SESSION_ID=${CLAUDE_SESSION_ID}' >> "$out_dir/subst.log"
echo '[BODY] PROJECT_DIR=${CLAUDE_PROJECT_DIR}' >> "$out_dir/subst.log"
echo '[BODY] SKILL_DIR=${CLAUDE_SKILL_DIR}' >> "$out_dir/subst.log"

# show all results
echo "=== subst.log (tier=plugin: SessionStart 経路, tier=fm: 自スキル frontmatter 経路, tier=body: 直前 echo) ==="
cat "$out_dir/subst.log"
```

## 判定ロジック

各行を見て：
- 値が UUID (例: `9307ae27-...`) → 事前置換 ✅
- 値が絶対パス (例: `/home/...`) → 事前置換 ✅
- 値が空 → 事前置換 ✅ だが値が unset
- 値が literal `${CLAUDE_SESSION_ID}` 等 → 事前置換 ❌

完了したら exit。
