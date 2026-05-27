---
name: fs-check
description: Reads the /tmp canary written by the plugin-level SessionStart hook, to test whether the hook (host) and the Bash tool (VM) share a filesystem.
user-invocable: true
---

# fs-check

plugin-level SessionStart hook が `/tmp/cowork-fs-canary.txt` に書き込みました。Bash tool から読めるか確認します。次の bash を実行してください。

```bash
echo "BODY host=$(hostname)"
echo "--- cat /tmp/cowork-fs-canary.txt ---"
cat /tmp/cowork-fs-canary.txt 2>&1
echo "--- ls ---"
ls -la /tmp/cowork-fs-canary.txt 2>&1
```

実行後、context にある `[FS-HOOK] wrote ... host=...` の行も併せて貼ってください（hook が動いた host 名が分かります）。

判定：

- cat が成功して `FS_CANARY_CONTENT` が出る + BODY host が hook host と同じ → **同一 filesystem**（CLI 予想）
- cat が `No such file or directory` + BODY host=`claude`（hook host と違う） → **hook はホスト / Bash tool は VM の別 filesystem**（Cowork 予想）
