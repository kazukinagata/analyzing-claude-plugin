# Windows Cowork SessionStart retest — 2026-09-30 JST

Verdict: PASS for a minimal plugin-level SessionStart command and context delivery.

## Environment and setup

- Windows Claude Desktop package observed in its UI accessibility tree: `Claude_2.16120.0.0_x64__pzs8sxrjxfjjc`.
- Local Cowork task, model displayed as Opus 5.5 (medium).
- Plugin `cowork-sessionstart-retest`, version 0.1.0, uploaded via ZIP; enabled toggle confirmed visually; UI listed one skill and one hook.
- ZIP: `dist/cowork-sessionstart-retest-20260930.zip`. Manifest, hooks and skill reside at archive root.
- Only hook: SessionStart; no matcher restriction; command `echo COWORK_SESSIONSTART_20260930_f7c2a91e`, timeout 10 seconds.
- Fresh task: `https://claude.ai/cowork/local_6a0422ab-aa75-45c9-ae78-060c37a80747`, title `Session start retest`.
- Invoked `/cowork-sessionstart-retest:check-sessionstart`.
- Skill prohibits tools, file inspection and commands. It contains the marker prefix but not the full expected token. The full token was not supplied in the user prompt.

## Observed response

Claude displayed the exact line:

```text
COWORK_SESSIONSTART_20260930_f7c2a91e
```

It reported that this arrived as SessionStart hook output labelled `SessionStart:startup hook success`. It also noted that the hook context appeared in the same message as the skill call, after the skill text, rather than in an earlier message.

Initially observed via the desktop screenshot. Subsequent audit-log inspection confirmed the exact marker with outcome=success, exit_code 0, and empty stderr; see `runtime-log-review.md` and `hook-log-evidence.json`. This establishes the minimal command/context canary, not environment propagation, script execution, other events or permission enforcement. Startup initially remained at `Starting up...`; its delay was not classified as hook failure.

## Follow-up sequence

Upload each probe ZIP separately and use a fresh local Cowork task. Keep raw session exports when available, recording hook command/stdout/stderr/exit status. Avoid concluding that PreToolUse did not fire from absent context stdout alone.

1. `cowork-env-probe:env-check`: compare plugin hook, skill frontmatter and Bash environment. Record ROOT/DATA/PROJECT and hostname.
2. `cowork-mp-disambig-probe:show-mp-disambig` via ZIP: compare literal quotes, HOME/PATH/unset-variable expansion and explicit bash wrapping. Despite its name, this retest uses ZIP only.
3. `cowork-mp-script-probe:show-mp-script`: check script launch through plugin-root paths; then `cowork-exec-form-probe:show-exec-form` for command/args form if accepted by current uploader.
4. `cowork-blockmethods-probe:block-methods`: plugin-level PreToolUse decision:block, permissionDecision:deny, exit 2, and an unmarked control. Inspect logs to distinguish execution failure from a decision being ignored.
5. `cowork-fm-bashblock-probe:fm-bashblock`: skill frontmatter PreToolUse with marked/unmarked Bash commands in a fresh session. Actual block plus control execution is the evidence; absent echo is not evidence of failure.
6. `cowork-envfile-probe:envfile-check` and `cowork-surface-probe:surface-check`: test environment-file propagation and multiple-statement output separately.
7. Only after the above: filesystem/path-layer probes, data persistence, SessionStart resume, and SubagentStart. Keep ZIP validation differences separate from runtime failures.

Initially stopped after the successful SessionStart canary as requested. The user subsequently authorized steps 1–4; results are recorded in `followup-1-4.md`. Steps 5–7 await further instruction. Probe plugin remains enabled.
