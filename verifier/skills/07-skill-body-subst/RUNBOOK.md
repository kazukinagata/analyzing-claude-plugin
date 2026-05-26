# RUNBOOK: 07-skill-body-subst

## 検証内容（§1.7）

skill body の `${VAR}` は **invoke 経路** でのみランタイムが置換する。Read tool 経由で SKILL.md を読むと literal のまま。

## 2 セッション運用

### セッション A：Read 経路（literal 期待）

```sh
cd /path/to/analyzing-claude-plugin
. scripts/_env.sh
claude --plugin-dir ./verifier
```

プロンプトで：
```
verifier/skills/07-skill-body-subst/SKILL.md の中で "CHECK_LINE:" で始まる行をそのまま教えてください。
```

Claude の返答を `findings/v.../07a-read-response.txt` に paste（手動）。**返答に literal `${CLAUDE_PLUGIN_ROOT}` を含むこと**が期待値。

### セッション B：invoke 経路（substituted 期待）

新しい claude セッション：
```
/verifier:07-skill-body-subst
```

完了して exit。`./scripts/assert.sh 07` で probe.log の `INVOKE_LINE: PLUGIN_ROOT_VALUE=/<abs>` を確認。

## 想定 verdict

- A の返答に literal `${CLAUDE_PLUGIN_ROOT}` あり、B の invoke で絶対 path に展開 → PASS
- 両方 literal → FAIL（invoke 経路の置換が壊れた）
- 両方 substituted → FAIL（Read 経路でも置換されるようになった = §1.7 が崩れた）
