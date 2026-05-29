---
name: bodypath
description: Shows what skill-body CLAUDE_PLUGIN_ROOT and friends substitute to on Mac Cowork, whether the VM Bash tool can use that path, and whether the Read tool can read a bundled file at that host path.
user-invocable: true
---

# bodypath

記事 §3「skill body の `${CLAUDE_PLUGIN_ROOT}` はホストパスに化ける」を Mac で検証する probe です。
skill body の `${...}` は env 非依存の事前置換なので Cowork でも置換されます。置換**値**（ホストパスの形）と、
そのパスを **VM 側 Bash tool が使えるか**、**Read tool で読めるか** を見ます。

## 手順 1: 置換値と VM Bash からの可否

次の bash を実行してください。

```bash
echo "BODY_ROOT=${CLAUDE_PLUGIN_ROOT}"
echo "BODY_DATA=${CLAUDE_PLUGIN_DATA}"
echo "BODY_SKILL_DIR=${CLAUDE_SKILL_DIR}"
echo "BODY_HOST=$(hostname)"
echo "--- can the VM Bash tool stat the substituted path? ---"
ls -la "${CLAUDE_PLUGIN_ROOT}/assets/marker.txt" 2>&1 | head -3
cat "${CLAUDE_PLUGIN_ROOT}/assets/marker.txt" 2>&1 | head -1
```

## 手順 2: Read tool でホストパスを読めるか

上の `BODY_ROOT` に出たパスを使い、**Read tool（bash ではなく）**で
`<BODY_ROOT>/assets/marker.txt` を読んでみてください。読めたら中身（`BODYPATH-MARKER-FILE-CONTENT ...`）を、
読めなければエラーを報告してください。

## 報告フォーマット

- `BODY_ROOT` / `BODY_DATA` / `BODY_SKILL_DIR` の値（パスの形：macOS path か `/var/folders/...` か等）
- `BODY_HOST`（`claude` のはず＝VM）
- 手順1の `ls` / `cat` が **成功したか失敗したか**（VM filesystem に存在するか）
- 手順2の **Read tool で読めたか**

## 判定

- BODY_ROOT が **macOS ホストパス**（`/Users/...` か `/var/folders/...`）に置換され、
  **VM Bash の `ls`/`cat` は失敗**、**Read tool では読める** → 記事 §3 と同じ構造（パスの形だけ macOS）。
- VM Bash でも普通に読めてしまう → VM が同じパスを見えている（DIVERGES）。
