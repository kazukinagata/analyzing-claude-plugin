# RUNBOOK: 11/12-block ペア

## 検証内容（§2.4 / §2.5）

skill frontmatter `PreToolUse:Skill` hook で別 skill の起動を block できる。**slash 起動では PreToolUse:Skill が発火しない**（§1.9）ため、target 側は自然文起動が必須。

## 厳密な手順制約

1. **対話開始直後の最初のプロンプト**で `/verifier:12-block-self` を slash 起動
2. Claude が step 1 alive-check を実行するのを待つ
3. **2 つ目のプロンプト**で「`11-block-target` skill を起動してください」と自然文で依頼
4. Claude が Skill tool を呼ぶ → 12 の frontmatter hook が block → reason が表示される
5. **3 つ目のプロンプト**で「11 の代わりに何が起きたか教えて」と聞き、ブロック理由を出力させる
6. exit

## 想定 verdict

- 11 の alive-check が log に**出ない**、cli output に `blocked by 12-block-self` が出る → PASS
- 11 の alive-check が出る → block 失敗 = FAIL
- Claude が 11 を slash で呼んだ → Skill tool 不発で block も不発（実は別経路）。やり直し
