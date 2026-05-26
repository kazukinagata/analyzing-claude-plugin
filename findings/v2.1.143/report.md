# Re-verification report — v2.1.143

Generated: 2026-05-18T15:55:57+09:00
Claude Code: 2.1.143 (Claude Code)

## verdicts

| probe | verdict | matched | missing | unwanted |
|---|---|---|---|---|
| 00-canary | CANARY-FAILED | 0 | 8 | 0 |
| 01-env-propagation | UNKNOWN | 0 | 12 | 0 |
| 02-substitution-allowlist | PARTIAL | 1 | 7 | 0 |
| 03-shell-binsh | UNKNOWN | 0 | 6 | 0 |
| 04-sensitive-leak | UNKNOWN | 0 | 5 | 0 |
| 05-userconfig-trigger | UNKNOWN | 0 | 2 | 0 |
| 06-marketplace-cache | UNKNOWN | 0 | 2 | 0 |
| 07-skill-body-subst | PARTIAL | 1 | 2 | 0 |
| 08-frontmatter-timing | PARTIAL | 1 | 2 | 0 |
| 09-slash-vs-natural | UNKNOWN | 0 | 4 | 0 |
| 10-parallel-hook-firing | UNKNOWN | 0 | 7 | 0 |
| 11-block-target | PARTIAL | 1 | 1 | 0 |
| 12-block-self | UNKNOWN | 0 | 3 | 0 |
| 13-cowork-pretooluse | UNKNOWN | 0 | 3 | 0 |
| 14-cowork-parser | UNKNOWN | 0 | 2 | 0 |
| 15-cowork-file-io | UNKNOWN | 0 | 3 | 0 |
| 16-cowork-path-forms | UNKNOWN | 0 | 4 | 0 |
| 17-cowork-bash-mount | UNKNOWN | 0 | 4 | 0 |
| 18-cowork-data-isolation | UNKNOWN | 0 | 6 | 0 |
| 19-cowork-resume | UNKNOWN | 0 | 2 | 0 |
| 20-cowork-validation | UNKNOWN | 0 | 3 | 0 |
| 21-cowork-connected-folder | UNKNOWN | 0 | 3 | 0 |

## ⚠ CANARY FAILED

probe 00-canary did not PASS. All subsequent verdicts should be treated as **CANARY-FAILED** regardless of the table above — the observation infrastructure itself is broken in this version.

## verdict meanings

- **PASS** — finding still holds (log matches expected)
- **FAIL** — finding has changed (alive-check present but expected pattern missing)
- **PARTIAL** — some subclaims match, some don't
- **UNKNOWN** — observation failed (alive-check missing, can't tell if finding changed)
- **DOC-ALIGNED** — finding changed in a direction that aligns with docs (bug fixed)
- **CANARY-FAILED** — observation infrastructure broken; probe 00 must PASS first
- **MANUAL-OK / MANUAL-NG** — auto judgment not possible; human review required
