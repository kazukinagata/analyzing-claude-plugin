# Re-verification report — v2.1.146 (CLI) / v2.1.146-148 (Cowork)

Generated (CLI baseline): 2026-05-21T16:31:55+09:00
Generated (Cowork round): 2026-05-22
Claude Code: 2.1.146 (Claude Code) — Cowork client may have advanced to v2.1.147 / v2.1.148 during the verification round (host CLI side advanced 2 versions during testing)

## Final verdicts

| probe | § | CLI verdict | Cowork verdict | overall |
|---|---|---|---|---|
| 00-canary | — | PASS | PASS (observation strategy confirmed) | PASS |
| 01-env-propagation | §1.1 | PASS | — (covered by 18) | PASS |
| 02-substitution-allowlist | §1.2 | PARTIAL | — | PARTIAL |
| 03-shell-binsh | §1.3 | PASS | — | PASS |
| 04-sensitive-leak | §1.4 | PASS | — | PASS |
| 05-userconfig-trigger | §1.5 | PARTIAL | — | PARTIAL |
| 06-marketplace-cache | §1.6 | PASS | — | PASS |
| 07-skill-body-subst | §1.7 | PASS | — | PASS |
| 08-frontmatter-timing | §1.8 | PASS | — | PASS |
| 08b-self-block-attempt | §1.8 | PASS | — | PASS |
| 09-slash-vs-natural | §1.9 / §6.2 | PASS | — | PASS |
| 10-parallel-hook-firing | §1.10 | PASS | — | PASS |
| 11-block-target | §2.4 | PASS | — | PASS |
| 12-block-self | §2.4 / §2.5 | PASS | — | PASS |
| 13-cowork-pretooluse | §2.5 / §2.4 | PASS (baseline) | PASS (block ineffective, mcp__workspace__bash confirmed) | PASS |
| 14-cowork-parser | §2.6 | PASS (baseline) | **DOC-ALIGNED** (`&&` / `\|\|` now run; `printf` still rejected) | DOC-ALIGNED |
| 15-cowork-file-io | §2.7 | PASS (baseline) | PASS (hook writes invisible to bash sandbox) | PASS |
| 16-cowork-path-forms | §2.8 | PASS (baseline) | **PARTIAL** (3 forms → 1 form; HOOK_SUBST / HOOK_ENV are literal `${VAR}` / `$VAR`) | PARTIAL |
| 16-follow-up: PATH expansion | §1.2 / §2.6 | — | **NEW** (top-level echo = literal emission; bash -c = real shell) | NEW |
| 17-cowork-bash-mount | §2.10 | PASS (baseline) | PASS (Pattern A works, Pattern B fails, `mkdir -p` Windows-path trap reproduced) | PASS |
| 18-cowork-data-isolation | §2.11 / §1.1 | PASS (baseline) | PASS for §2.11; **REGRESSION** for §1.1 (plugin-level hook env no longer has CLAUDE_PLUGIN_ROOT / DATA on Cowork) | PASS + regression |
| 19-cowork-resume | §2.1 / §2.12 | PASS (baseline) | PASS (resume reuses same VM / user / cwd; SessionStart source=resume re-fires) | PASS |
| 20-cowork-validation | §2.3 | PASS (baseline) | PASS (Findings A-F from install-time bisect: kebab-case enforcement, `${VAR^^}` reject, YAML strict, description `${CLAUDE_*}` token reject, content threshold) | PASS |
| 21-cowork-connected-folder | §2.9 | PASS (baseline) | PASS + virtio-fs architecture exposed + rm guard discovered | PASS |

## verdict meanings

- **PASS** — finding still holds (log matches expected)
- **FAIL** — finding has changed (alive-check present but expected pattern missing)
- **PARTIAL** — some subclaims match, some don't
- **UNKNOWN** — observation failed (alive-check missing, can't tell if finding changed)
- **DOC-ALIGNED** — finding changed in a direction that aligns with docs (bug fixed) or is no longer a constraint
- **CANARY-FAILED** — observation infrastructure broken; probe 00 must PASS first
- **NEW** — observation not anticipated by research, captured here for the first time
- **REGRESSION** — finding worse than research baseline (a previously-working feature has broken)

## Cowork architecture model (newly established)

The Cowork verification round reorganized our understanding of how Claude Desktop's Cowork environment is constructed. The model that explains every observation we made:

1. **Cowork VM is host-adjacent**, not a remote cloud VM. It runs alongside the user's Windows + WSL stack and shares the host filesystem subset via **virtio-fs FUSE bind mounts**. See probe 21 mount output.
2. **Plugin-level hooks execute on the user's local Claude Desktop host** (PATH contains `/mnt/c/Users/knaga/...`, `/sessions/` directory does not exist there). Hooks never enter the Cowork VM.
3. **The Bash tool (surfaced as `mcp__workspace__bash`) executes inside the Cowork VM** (`hostname=claude`, working directory `/sessions/<codename>/`).
4. **The same Cowork VM is shared across all of one user's chats**. Each chat gets its own Linux user account, and cross-chat isolation is enforced at the POSIX file-permission level — foreign session directories are owned by `nobody:nogroup` and have `drwxr-x---`.
5. **CLI claude sessions also leave traces in the same `/sessions/` namespace** (the `cli-<hex>` directories), suggesting the same VM serves both Cowork and CLI usage on this user's machine.
6. **Hook command execution has two distinct modes**:
   - Top-level `echo X` → literal text emission, no shell, no `$VAR` / `${VAR}` expansion
   - `bash -c "..."` → real bash subprocess with full POSIX expansion
   This explains the apparent §2.8 "three path forms" collapsing to one observable form: top-level echo just emits the substitution-marker string verbatim.

## Net divergence from research v2.1.119

| Section | v2.1.119 claim | v2.1.146-148 reality | Direction |
|---|---|---|---|
| §1.1 plugin-level hook env | CLAUDE_PLUGIN_ROOT / DATA SET | Both UNSET on Cowork (bash -c "echo $CLAUDE_PLUGIN_ROOT" returns empty) | Regression |
| §1.2 hook command `${VAR}` substitution | Pre-substituted by Claude Code | Literal on top-level emission; only `bash -c` wrapper triggers real shell expansion | Worse than docs |
| §2.3 Cowork validator | Generic "Plugin validation failed" | Same generic message, but new strict rules: kebab-case enforcement, `${VAR^^}` reject, YAML closing-quote strict, `${CLAUDE_*}` and `<...>` markers in description reject, accumulated-content threshold | Stricter |
| §2.6 hook command parser | echo + bash whitelist, `&&` / `\|\|` fragment | `&&` / `\|\|` now run correctly inside bash -c; `printf` still rejected | Relaxed (DOC-ALIGNED) |
| §2.8 path forms | 3 forms (Windows / MSYS / VM Linux) | 1 observable form (BODY_SUBST Windows + forward-slash); other 2 forms appear as literal `${VAR}` / `$VAR` in hook context | Narrowed |
| §2.9 connected folder | RW after request_cowork_directory approval | Same, plus newly observed `rm` guard — RW mounts disallow deletion via bash | Stricter on delete |
| §2.10 bash mount | Read-only mount confirmed | Same, plus mechanism revealed (virtio-fs FUSE) | Same + architecture revealed |
| §2.11 cross-chat DATA isolation | Per-chat DATA dir, ROOT shared | Confirmed, mechanism is POSIX user/group permission. /sessions/ top-level is world-listable → codename metadata leak | Same + new metadata leak |
| §2.12 same-chat suspend/resume | Same VM, same DATA | Confirmed; same user account too | Same |
| §2.1 SessionStart source=resume | Re-fires with source=resume | Confirmed; UserPromptSubmit hooks also re-fire on resume | Same |
| §2.5 plugin-level PreToolUse block | Ineffective on Cowork | Same; Bash tool name is `mcp__workspace__bash` | Same |
| §2.7 hook file I/O isolation | Hook writes invisible to bash sandbox | Same; root cause now understood (hooks run on local host, bash tool runs on VM, separate filesystems) | Same + cause revealed |

## Notable new findings worth recording

1. **virtio-fs / host-adjacent VM architecture** (§2.9, §2.7 root cause)
2. **per-user shared VM + per-chat POSIX user isolation** (§2.11)
3. **/sessions/ codename inventory metadata leak** (§2.11)
4. **CLI session traces co-located with Cowork sessions** (`cli-<hex>` dirs)
5. **Cowork hook command two-mode execution** (literal vs bash -c)
6. **rm guard on RW connected folders** (§2.9)
7. **Cowork validator rules: kebab-case enforcement / `${VAR^^}` reject / YAML strict / description tokens / content threshold** (§2.3, Findings A-F)
8. **`CLAUDE_CODE_ENTRYPOINT` UNSET in Cowork's Bash tool subprocess** (de facto CLI vs Cowork discriminator)

## Source artifacts

- `findings/v2.1.146/observations.md` — full per-probe observation text (≈ 1300 lines)
- `findings/v2.1.146/expected/` — expected log patterns for CLI assert.sh
- `findings/v2.1.148/verifier-cowork.zip` — full Cowork-installable plugin
- `findings/v2.1.148/verifier-cowork-{parser-tests,path-forms,expansion-test,data-isolation}.zip` — focused Cowork probe zips
- `scripts/build-*.sh` — zip builders + bisect tooling used during the Cowork install debugging phase

## Next steps (not done in this round)

- Propose patches to research.md based on the diff above (per-section diff format already drafted in observations.md)
- Generalize the verifier into a "Cowork-compat plugin lint" tool that runs the install-time bisect rules against new plugin candidates
- Investigate whether hook process is **always** local or only on Windows hosts (Mac / Linux Cowork might run hooks differently)
