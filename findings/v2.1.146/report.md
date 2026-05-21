# Re-verification report — v2.1.146

Generated: 2026-05-21T16:31:55+09:00
Claude Code: 2.1.146 (Claude Code)

## verdicts

| probe | verdict | matched | missing | unwanted |
|---|---|---|---|---|
| 00-canary | PASS | 8 | 0 | 0 |
| 01-env-propagation | PASS | 12 | 0 | 0 |
| 02-substitution-allowlist | PARTIAL | 6 | 2 | 0 |
| 03-shell-binsh | PASS | 7 | 0 | 0 |
| 04-sensitive-leak | PASS | 5 | 0 | 0 |
| 05-userconfig-trigger | PARTIAL | 1 | 1 | 0 |
| 06-marketplace-cache | PASS | 2 | 0 | 0 |
| 07-skill-body-subst | PASS | 3 | 0 | 0 |
| 08-frontmatter-timing | PASS | 3 | 0 | 0 |
| 08b-self-block-attempt | PASS | 3 | 0 | 0 |
| 09-slash-vs-natural | PASS | 4 | 0 | 0 |
| 10-parallel-hook-firing | PASS | 7 | 0 | 0 |
| 11-block-target | PASS | 2 | 0 | 0 |
| 12-block-self | PASS | 3 | 0 | 0 |
| 13-cowork-pretooluse | PASS | 3 | 0 | 0 |
| 14-cowork-parser | PASS | 6 | 0 | 0 |
| 15-cowork-file-io | PASS | 3 | 0 | 0 |
| 16-cowork-path-forms | FAIL | 0 | 4 | 0 |
| 17-cowork-bash-mount | FAIL | 0 | 4 | 0 |
| 18-cowork-data-isolation | FAIL | 0 | 6 | 0 |
| 19-cowork-resume | FAIL | 0 | 2 | 0 |
| 20-cowork-validation | PASS | 4 | 0 | 0 |
| 21-cowork-connected-folder | FAIL | 0 | 3 | 0 |

## Cowork-only probes (deferred until Cowork verification pass)

probes 16, 17, 18, 19, 21 are designed to run only inside Claude Desktop's Cowork environment (path forms / bash mount / DATA isolation / resume / connected folders). They cannot be exercised from the CLI. If they appear as FAIL or UNKNOWN above, that is the expected baseline — read findings/v.../observations.md for the deferred items list.

## verdict meanings

- **PASS** — finding still holds (log matches expected)
- **FAIL** — finding has changed (alive-check present but expected pattern missing) — for Cowork-only probes, this just means the probe wasn't run from the CLI side
- **PARTIAL** — some subclaims match, some don't
- **UNKNOWN** — observation failed (alive-check missing, can't tell if finding changed)
- **DOC-ALIGNED** — finding changed in a direction that aligns with docs (bug fixed)
- **CANARY-FAILED** — observation infrastructure broken; probe 00 must PASS first
- **MANUAL-OK / MANUAL-NG** — auto judgment not possible; human review required
