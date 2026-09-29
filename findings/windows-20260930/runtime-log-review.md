# Cowork runtime log review — 2026-09-30 JST

The user requested inspection of the execution logs after the initial screen-based retest. No new Cowork probe was run. Selected original hook responses, excluding unrelated plugin context and conversation text, are preserved in `hook-log-evidence.json`.

## Sources and attribution

Source root: `%APPDATA%/Claude/local-agent-mode-sessions/fee811d1-83d8-420f-bcaa-79199650d487/64e1cdfd-e87f-495a-9275-693bd8d6f659/`.

| Task | Directory containing audit.jsonl |
| --- | --- |
| Session start retest | `6a0422ab` |
| 環境変数伝播の追試 | `43598c76` |
| MP_DA行の報告 | `4c2e4d53` |
| スクリプト起動とexec形式の追試 | `d8d85982` |
| Block-methods skill testing | `5b7e16ed` |

The script/exec task's user prompt timestamp is `2026-09-29T22:35:18.292Z` (2026-09-30 JST). Its hook responses run from 22:35:27Z to 22:35:30Z. Global `cowork_host_loop_debug.log` matches were from May and were excluded from this retest.

Audit hook_started records contain IDs but no command/args. For the exec probe, consecutive starts on lines 22–28 follow the seven entries of the repository's hooks.json, and stdout from entries 1–3 and 7 confirms the order. IDs from lines 25–27 match the direct-script, Bash-script and echo error responses below. Attribution of the direct-script error uses this ordering; the Bash-script and echo stderr additionally identify the target.

## Resolved failures

| Probe variant | Source line in d8d85982/audit.jsonl | exit_code | stderr |
| --- | --- | --- | --- |
| execdirect: spawn bundled .sh directly | 32 | 1 | `Failed to run: EFTYPE: inappropriate file type or format, uv_spawn` |
| execbash: Bash reads bundled .sh | 63 | 127 | `/bin/bash: C:UsersknagaAppDataRoamingClaude...rpmplugin_01TijXyb5dhhRNYPpfHebrLX/hooks/exec-marker.sh: No such file or directory` |
| echo command with args | 33 | 1 | `Error occurred while executing hook command: Executable not found in $PATH: "echo"` |

All three have empty stdout and outcome=error. These are confirmed launch failures, not merely absent context markers. The same error signatures also occur in the environment, quoting and block-test tasks, where this plugin was enabled concurrently.

- **Direct .sh**: native spawn rejected the file format. This differs from invoking the same kind of script through a shell. The log reports exit_code 1; it does not establish that the script body started and returned 1.
- **Bash script**: the target is a populated Windows installation path whose backslash separators have disappeared (`C:Usersknaga...`). Placeholder/path resolution therefore produced a nonempty target somewhere in the launch route. An empty plugin environment variable alone does not explain this failure. Backslash consumption by shell parsing is a plausible explanation, but the log does not expose the exact constructed command line or original argv, so that implementation detail remains an inference.
- **echo**: the launcher attempted executable lookup for echo and failed. Echo worked inside `bash -c` in the control. No plugin variable is needed for this failure.

Audit lines 62, 64, 65 and 66 respectively confirm the empty placeholder-position output, empty plugin environment, WSL markers, and successful Bash echo control, each with exit_code 0. `EXEC_ARGS_PLACEHOLDER=[]` alone does not prove the original argument was empty: positional argument forwarding or shell reconstruction could also affect `$1`. Consequently, the previous inference that ROOT was simply empty and caused both script failures is withdrawn.

## Other confirmations

The minimal canary audit records the exact marker with outcome=success, exit_code 0 and empty stderr. Shell-form environment/quoting/script outputs in all four later tasks also have exit_code 0 and empty stderr, corroborating the screen reports. In d8d85982, shell script success appears at lines 44 and 61.

The block-test audit contains three separate tool_result records with is_error=true: `BLK-decision`, `BLK-permission`, and the exit-2 hook error identifying `cowork-blockmethods-probe@inline`. The fourth result contains `RESULT CONTROL ran host=claude`. This corroborates enforcement without relying only on Claude's summary. Audit did not record separate PreToolUse hook_response exit codes, so exit 2 is identified by probe branch and tool error rather than a separate numeric audit field.

## Remaining limits

Subsequent fresh execution with a new probe independently checked the environment using direct printenv calls and an env filter. All three variables were absent in the tested command/args Bash process, whereas the same session's shell-form hook returned their values. See `exec-env-retest.md`; this refines the earlier wording "empty plugin environment variables" to "unset in the tested Bash process" without resolving the launcher/WSL boundary responsible.

Exact executable paths and constructed argv/command lines were not exposed by the inspected records. Git Bash/MSYS vs WSL execution routes remain strong inferences from their output signatures. No conclusion about general script execution with a corrected absolute path, the exact placeholder expansion layer, skill-frontmatter hooks, userConfig, env files, persistence, resume or SubagentStart is added. Steps 5–7 remain unrun. Original full logs are kept outside Git; only probe-specific selected records are committed.
