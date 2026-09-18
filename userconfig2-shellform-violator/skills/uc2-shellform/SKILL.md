---
name: uc2-shellform
description: shell-form hook command が ${user_config.*} を参照したとき、post-2.1.207 の仕様どおり「エラーで実行されない」のかを確認する probe。install 時の validator エラー / SessionStart の出力有無 / 前後 entry が巻き添えになるかを見る。
user-invocable: true
---

# uc2-shellform

**問い**: shell form の hook が `${user_config.*}` を参照したとき、何が起きるか。

docs（v2.1.207 以降）:
> A plugin hook whose `command` references `${user_config.*}` fails with an error instead of running.
> Before v2.1.207, shell-form plugin hooks also substituted `${user_config.*}`.

## 観測ポイント

1. **install 自体が通るか**（validator が zip を弾くか、install はできて実行時に落ちるか）
2. SessionStart context に出た行を報告：
   - `VIO-CTL before=alive` が出るか
   - `VIO-SHELL ...` が出るか（出るなら旧挙動＝置換、literal `${user_config.vio_plain}` なら未置換で実行、出ないなら仕様どおり fail）
   - `VIO-CTL after=alive` が出るか（**巻き添え判定**：これが消えるなら失敗が同一 matcher の他 entry を道連れにしている）
3. エラーメッセージが**どこに出るか**（UI トースト / context / 完全に silent）

## 判定

| 観察 | 意味 |
|---|---|
| before/after のみ出て VIO-SHELL 無し + エラー表示あり | docs どおり（entry 単位で fail、隔離されている） |
| before/after のみ出て エラー表示なし | **silent skip**（旧 Cowork 挙動が残存＝debug 困難） |
| `VIO-SHELL vio_plain=[VIOPLAIN-VAL]` | **旧挙動が残っている**（docs と不一致） |
| `VIO-SHELL vio_plain=[${user_config.vio_plain}]` | 置換されず literal のまま shell に渡っている |
| before も after も出ない | plugin 全体が落ちている |
