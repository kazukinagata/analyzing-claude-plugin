---
name: 21-cowork-connected-folder
description: §2.9. Cowork sandbox limits write/edit/bash to outputs/ by default; plugin dir is read-only; request_cowork_directory grants RW to arbitrary host folders.
user-invocable: true
---

# 21-cowork-connected-folder

§2.9 — 接続フォルダの権限境界。

## step 1: alive-check と write 試行

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="${VERIFIER_VERSION_DIR:-v-unknown}"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
{
  printf '[21-BODY %s] tag=alive-check\n' "$(date -Iseconds)"
  printf '[21-BODY] CLAUDE_PROJECT_DIR=[%s]\n' "${CLAUDE_PROJECT_DIR-(unset)}"
  printf '[21-BODY] CLAUDE_PLUGIN_ROOT=[%s]\n' "${CLAUDE_PLUGIN_ROOT-(unset)}"
} | tee -a "$out_dir/probe.log"
mkdir -p "${CLAUDE_PROJECT_DIR}/outputs" 2>/dev/null
echo
echo "=== Write trial: outputs/ (expected OK on Cowork) ===" | tee -a "$out_dir/probe.log"
{ echo "test-21-outputs" > "${CLAUDE_PROJECT_DIR}/outputs/canary-21.txt" 2>&1 && echo "outputs write: OK" || echo "outputs write: FAIL"; } | tee -a "$out_dir/probe.log"
echo
echo "=== Write trial: plugin dir (expected FAIL on Cowork) ===" | tee -a "$out_dir/probe.log"
{ echo "test-21-plugin" > "${CLAUDE_PLUGIN_ROOT}/canary-21.txt" 2>&1 && echo "plugin-dir write: OK" || echo "plugin-dir write: FAIL"; } | tee -a "$out_dir/probe.log"
```

## step 2: Cowork で request_cowork_directory tool 試行（あれば）

Claude にお願いしてください：「`~` への `request_cowork_directory` を実行して、承認したら `~/canary-21-host.txt` に書き込みテストして」（Cowork 環境でのみ動作）。

完了して exit、`./scripts/assert.sh 21`。
