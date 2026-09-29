# Windows Cowork ZIP hook retest: steps 1–4

Date: 2026-09-30 JST. Claude Desktop package observed: 2.16120.0.0; local Cowork, Opus 5.5 medium.

## Setup and evidence limits

The five existing probes were packaged without source changes as `dist/<probe>-20260930.zip`, with manifest/hooks/skills at archive root, and uploaded together through Customize → Plugins → Upload. All five showed Added. They and the minimal SessionStart canary were enabled simultaneously, alongside existing user plugins. Each numbered test used a fresh task; prefixes distinguish the probes. This differs from the originally proposed separate-plugin upload procedure and is not an isolated single-plugin reproduction.

Steps 1–3 were observed from Claude's desktop response reporting received hook context. Hooks were not rerun to fabricate missing output. Runtime logs/session exports were not inspected, so missing SessionStart output does not independently establish an execution failure. Step 4 was additionally verified by expanding all four actual Bash request/result cards in the UI. Steps 5–7 were not run. Probe plugins remain installed/enabled.

## 1. Environment propagation

Probe: `cowork-env-probe:env-check`. Task: `環境変数伝播の追試`.

Plugin SessionStart output had populated `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, and `CLAUDE_PROJECT_DIR`, all pointing into `C:/Users/knaga/AppData/Roaming/Claude/local-agent-mode-sessions/...`. ROOT ended at an installed `rpm/plugin_*` directory; DATA ended at `.claude/plugins/data/cowork-env-probe-inline`; PROJECT ended at `host-cwd`. Session-specific IDs are abbreviated here.

```text
OPT_HELLO=[] ENTRY=[local-agent] HOST=[LAPTOP-BKGB6100]
[BODY] ROOT=[(unset)] DATA=[(unset)] PROJECT=[(unset)] ENTRY=[(unset)] HOST=[claude]
```

The body used the sandbox Bash tool. Hook environment propagation improved relative to the earlier empty ROOT/DATA/PROJECT observation, but those variables were not inherited by the sandbox body. No userConfig value was entered, so empty OPT_HELLO is not evidence of configuration propagation failure. Plugin PreToolUse and skill-frontmatter output were not present in reported context; no non-execution conclusion is drawn from that absence. Resume was excluded.

## 2. Quoting and shell expansion

Probe: `cowork-mp-disambig-probe:show-mp-disambig`. Task: `MP_DA行の報告`. All 12 expected lines were reported.

```text
MP_DA_CONTROL=static_marker_no_var
MP_DA_DQ=double-quoted
MP_DA_DQ_INNER=hello-middle-world
MP_DA_HOME=/c/Users/knaga
MP_DA_HOME_BRACE=/c/Users/knaga
MP_DA_NUL=
MP_DA_BASH_HOME=/c/Users/knaga
MP_DA_BASH_HOST=LAPTOP-BKGB6100
MP_DA_BASH_WSL_LIB=absent
MP_DA_BASH_MNT_C=absent
```

Both `MP_DA_PATH` and `MP_DA_BASH_PATH` started `/mingw64/bin:/usr/bin:/c/Users/knaga/bin:/bin:` and continued with Windows paths in `/c/...` form; full PATH omitted here. Quotes were parsed and variables expanded. Paths and absent WSL markers suggest Git Bash/MSYS execution for shell-form hooks; the actual executable was not inspected.

## 3. Plugin scripts and command/args form

Probes: `cowork-mp-script-probe:show-mp-script` and `cowork-exec-form-probe:show-exec-form`. Task: `スクリプト起動とexec形式の追試`.

Shell-form results:

```text
MP_SCRIPT_CONTROL=static_marker_no_var
MP_SCRIPT_ECHO_BARE=C:/Users/knaga/AppData/Roaming/Claude/local-agent-mode-sessions/.../rpm/plugin_...
MP_SCRIPT_ECHO_SQ=${CLAUDE_PLUGIN_ROOT}
MP_SCRIPT_MARKER form=topbare reached=yes ...
MP_SCRIPT_MARKER form=bashbrace reached=yes ...
```

Both marker scripts reported their `hooks/marker.sh` path, populated ROOT_ENV/DATA_ENV, and HOST=`LAPTOP-BKGB6100`. Direct quoted script invocation and explicit `bash -c` invocation therefore reached the bundled script. Single quotes kept the variable literal, consistent with shell expansion; this does not support blanket textual substitution before shell parsing. Ellipses above abbreviate observed paths/fields.

Command/args-form ZIP was accepted, and these lines arrived:

```text
EXEC_CONTROL=static_no_var
EXEC_ARGS_PLACEHOLDER=[]
EXEC_ENV_ROOT=[] EXEC_ENV_DATA=[] EXEC_ENV_PROJ=[]
EXEC_HOST=LAPTOP-BKGB6100 EXEC_WSL_LIB=present EXEC_MNT_C=present
```

Not received: `EXEC_MARKER form=execdirect`, `EXEC_MARKER form=execbash`, `EXEC_ECHO_BUILTIN=`. Thus command/args form works for at least the Bash control, but plugin environment/path handling is not equivalent to shell form. Present WSL markers suggest a WSL route for this form. The empty positional argument alone does not identify which expansion layer produced it. Missing markers are unresolved without runtime stderr/exit logs; do not label them proven launch failures.

## 4. Plugin PreToolUse blocking

Probe: `cowork-blockmethods-probe:block-methods`. Task: `Block-methods skill testing`.

Four separate `mcp__workspace__bash` requests were made in the specified order, without bypass/retry. Expanded request/result cards confirmed:

| Request marker | Method | Actual result |
| --- | --- | --- |
| M_DECISION | `decision:block` | Error: `PreToolUse:mcp__workspace__bash hook error: BLK-decision` |
| M_PERMISSION | `hookSpecificOutput.permissionDecision:deny` | Error: `PreToolUse:mcp__workspace__bash hook error: BLK-permission` |
| M_EXIT2 | exit 2 | PreToolUse hook error containing the hook command and `No stderr output`; no RESULT output |
| CONTROL | unmarked | Response: `RESULT CONTROL ran host=claude` |

The exit-2 error identified `cowork-blockmethods-probe@inline` as its source in the displayed report. The two JSON methods returned their probe-specific rejection reasons, providing evidence that the hook executed and its decision was enforced. All three marked commands were prevented; the control executed. This changes the earlier observation that plugin-level blocking was ignored. Scope is this matcher and sandbox Bash tool, not all tools or skill-frontmatter hooks.

## Outcome

The old broad conclusion that Windows Cowork plugin hooks do not work no longer describes this environment. Shell-form SessionStart context, environment expansion, bundled scripts, and plugin PreToolUse blocking worked in these tests. Command/args form still has distinct environment/path behavior requiring further diagnosis. Await user instruction before steps 5–7.
