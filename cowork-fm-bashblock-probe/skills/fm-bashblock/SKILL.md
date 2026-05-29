---
name: fm-bashblock
description: Proves whether a skill frontmatter PreToolUse Bash hook fires on Cowork by emitting only a block decision (no echo). A marked bash should be blocked even though no frontmatter stdout surfaces.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash|mcp__workspace__bash"
      hooks:
        - type: command
          command: 'bash -c ''input=$(cat); if printf "%s" "$input" | grep -q "FMBLOCK_MARKER"; then printf "%s" "{\"decision\":\"block\",\"reason\":\"FM-BASH-BLOCKED-NO-ECHO\"}"; fi'''
---

# fm-bashblock

この skill の frontmatter に **PreToolUse(Bash) hook** が 1 つだけ入っています。その hook は
**echo を一切せず**、bash の中に `FMBLOCK_MARKER` という文字列が含まれるときだけ
`{"decision":"block","reason":"FM-BASH-BLOCKED-NO-ECHO"}` という **block 決定だけ**を出します。

狙い: frontmatter hook の **stdout は Cowork で context に surface しない**ことは既に分かっている。
ここで **block 決定（制御）だけ**を使えば、echo が見えなくても「frontmatter PreToolUse:Bash hook が
実際に発火しているか」を直接判定できる。

> ⚠ 必ず **resume を挟まない fresh session** で実行してください（frontmatter hook 登録は resume で失効するため）。

## 手順

次の 2 つの bash を**順に、それぞれ別々に**実行してください。

### 1. marked（ブロックされるはず）

```bash
echo "FM-MARKED ran (should be BLOCKED) FMBLOCK_MARKER host=$(hostname)"
```

### 2. control（マーカー無し・通るはず）

```bash
echo "FM-CONTROL ran (should run) host=$(hostname)"
```

## 報告フォーマット

各コマンドについて、次のどちらかを明記してください：

- **ブロックされた**: reason（`FM-BASH-BLOCKED-NO-ECHO`）が出て、`echo` の出力は出なかった
- **実行された**: `FM-MARKED ran ...` / `FM-CONTROL ran ... host=...` の出力が出た

## 判定

- marked が **ブロック** + control が **実行** → **frontmatter PreToolUse:Bash hook は Mac で発火している**
  （echo は surface しないが block 決定は honor される、が直接証明される）。
- marked も **実行されてしまう** → frontmatter PreToolUse:Bash hook は発火していない
  （block も stdout も効かない = Windows と同じ「frontmatter hook 機能せず」側）。
