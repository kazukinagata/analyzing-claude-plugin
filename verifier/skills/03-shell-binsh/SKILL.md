---
name: 03-shell-binsh
description: Probe that hook commands run under /bin/sh (dash on WSL Ubuntu), not bash (§1.3). Bash-specific constructs should produce Bad substitution / syntax errors.
user-invocable: true
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: '{ printf "[03-FM-bashisms %s] BASH_VERSION=[%s] uppercased=[${PWD^^}]\n" "$(date -Iseconds)" "$BASH_VERSION" 2>&1; } >> "$CLAUDE_PROJECT_DIR/findings/v$(claude --version 2>/dev/null | awk "{print \$1}")/${CLAUDE_SESSION_ID:-no-sid}/probe.log" 2>&1'
---

# 03-shell-binsh

§1.3 — hook 実行は `/bin/sh`（dash）。bash 固有構文で Bad substitution / syntax error。

## step 1: alive-check と shell 実体判定

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
out_dir="$proj/findings/$ver/$sid"
mkdir -p "$out_dir"
{
  printf '[03-BODY %s] tag=alive-check\n' "$(date -Iseconds)"
  printf '[03-BODY] /bin/sh -> %s\n' "$(readlink -f /bin/sh)"
  /bin/sh -c 'printf "[03-binsh] BASH_VERSION=[%s] RANDOM=[%s]\n" "$BASH_VERSION" "$RANDOM"'
  /bin/sh -c '[[ "$X" = "y" ]] && echo "[[ works"' 2>&1 || printf '[03-binsh] [[ syntax error (expected)\n'
  /bin/sh -c 'echo "${PWD^^}"' 2>&1 || printf '[03-binsh] ^^ syntax error (expected)\n'
} | tee -a "$out_dir/probe.log"
```

## step 2: hooks.log にも shell error が出ているか確認

```bash
proj="${CLAUDE_PROJECT_DIR:-$PWD}"
ver="v$(claude --version 2>/dev/null | awk '{print $1}' || echo unknown)"
sid="${CLAUDE_SESSION_ID:-no-sid}"
echo "=== probe.log (shell test) ==="
tail -n 30 "$proj/findings/$ver/$sid/probe.log"
echo
echo "=== hooks.log (frontmatter hook bashism attempt) ==="
grep -A2 '03-FM-bashisms' "$proj/findings/$ver/$sid/hooks.log" 2>&1 || echo "(no match)"
```

完了して exit、`./scripts/assert.sh 03`。
