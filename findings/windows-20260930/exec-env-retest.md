# command/args environment recheck — 2026-09-30 JST

Verdict: in the tested command/args `bash -c` process, CLAUDE_PLUGIN_ROOT, CLAUDE_PLUGIN_DATA and CLAUDE_PROJECT_DIR are absent, not merely set to empty strings. The same task's shell-form hook receives all three.

## Setup

Fresh Cowork task `R2行と環境変数の再テスト`, audit directory `513436fe`, first hook response at `2026-09-29T23:30:48.170Z` (08:30:48 JST). New plugin `cowork-exec-env-retest` version 0.1.0 uploaded via ZIP. It contains seven SessionStart entries. Prior five probes had been removed in the visible UI before this run and were not restored; existing unrelated user plugins remained. This is not a reproduction with all unrelated plugins disabled.

The skill reports only received hook context, without file reads or command reruns. Results were taken directly from `audit.jsonl`, not just the model's summary. Selected records are saved in `exec-env-retest-evidence.json`.

## Independent reads

Original style uses command substitutions inside echo. To avoid relying on that mechanism, new exec-form entries each used `command: bash`, with args `[-c, <one of the strings below>]`:

```sh
echo R2_ROOT_BEGIN; printenv CLAUDE_PLUGIN_ROOT
echo R2_DATA_BEGIN; printenv CLAUDE_PLUGIN_DATA
echo R2_PROJECT_BEGIN; printenv CLAUDE_PROJECT_DIR
echo R2_ENV_BEGIN; env | grep -E '^CLAUDE_(PLUGIN_ROOT|PLUGIN_DATA|PROJECT_DIR)='
```

None contains dollar expansion or command substitution. The env filter restricts output to the three investigated variables.

| Audit source line | Variant | stdout after marker | stderr | exit_code |
| --- | --- | --- | --- | --- |
| 22 | ROOT printenv | none | empty | 1 |
| 20 | DATA printenv | none | empty | 1 |
| 21 | PROJECT printenv | none | empty | 1 |
| 23 | env filter | no matching entries | empty | 1 |
| 25 | original command-substitution form | `R2_ORIGINAL_ROOT=[] DATA=[] PROJECT=[]` | empty | 0 |
| 24 | exec Bash echo control | `R2_EXEC_CONTROL` | empty | 0 |
| 13 | shell form printenv of all three | three populated Windows paths | empty | 0 |

The individual printenv exit statuses and absence from env distinguish unset variables from variables set to empty strings. The original echo exits successfully despite the inner reads returning no value, so its exit_code 0 does not establish successful environment lookup. The error outcome hides the new direct-read markers from successful hook context, which is why inspecting logs was necessary.

Scope: environment of the Bash process reached by the tested command/args route. This does not prove every executable launched using command/args receives no plugin env: the WSL boundary or shell startup may be responsible. Exact executable/argv construction was not recorded.

## What the earlier broken path actually looked like

Earlier execbash stderr (task d8d85982, audit line 63) used:

```text
C:UsersknagaAppDataRoamingClaudelocal-agent-mode-sessions...rpmplugin_01TijXyb5dhhRNYPpfHebrLX/hooks/exec-marker.sh
```

The `...` abbreviates session identifiers here. Between `C:` and `hooks`, Windows directory separators are gone; the final `/hooks/exec-marker.sh` slashes remain. A normal Windows installation path would use separators such as `C:\Users\knaga\AppData\Roaming\Claude\...\rpm\plugin_...\hooks\exec-marker.sh`. The malformed string does not denote that file. A WSL target would also need an appropriate path representation such as `/mnt/c/...`; correcting that was not tested.

Backslashes being consumed by shell parsing is a plausible explanation, not an observed exact argv transformation. This nonempty installed-plugin path and the absent environment variables are separate observations. Direct native .sh spawn and direct echo lookup have their own errors, described in `runtime-log-review.md`.
