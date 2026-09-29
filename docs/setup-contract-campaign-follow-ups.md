# Setup-contract campaign follow-ups (#3138)

Recorded positions on the four follow-ups surfaced by the #3111 / #3112 / #3113 / #3127
campaign and bundled in [#3138](https://github.com/melodic-software/claude-code-plugins/issues/3138).
This is not an unpaid fleet sweep. Each row is adopt (the position is the close) or defer
(work remains, but the parent issue does not stay open as a campaign).

**Claim:** The four follow-ups are settled as the table below. No toolchain bump, no
Windows suite rewrite, no `CLAUDE_PLUGIN_ROOT` call-site fleet, and no
`check-drive-root-litter.sh` scope change ships in this record.

**Basis:** #3138 (filed 2026-08-23; triage 2026-08-23 against `main` at `393658c`;
decision-ready split 2026-09-06). Origin/main 2026-09-29: root `package.json` pins
`@anthropic-ai/claude-code` at **2.1.283**; the plugins reference documents
`${CLAUDE_PLUGIN_ROOT}` substitution in skill and agent content, and
[ADR 0007](adr/0007-host-per-model-doctrine-outside-skill-private-surfaces.md) holds the
version-stamped record of which surfaces expand it; `worktree-root-doctor.test.sh`
and `worktree-add-containment-gate.test.sh` still have no Windows host-skip (unlike #3683's
Git Bash path-form suites); `scripts/check-drive-root-litter.sh` is already a host-wide
advisory scan (its "ADVISORY BY DEFAULT" header; `DRIVE_ROOT_LITTER_IGNORE_SINKS` opt-out).

**As of:** 2026-09-29.

**Recheck:** any Claude Code upgrade; `package.json` pin lags a measured CLI used for a
version-stamped claim; a Windows host re-runs the two worktree suites and files a
support-or-skip issue; the plugins reference drops skill/agent content substitution; or a
maintainer wires `check-drive-root-litter.sh` into a required live lane.

## Positions

| Follow-up | Position | Adopt / defer |
| --- | --- | --- |
| 1. `CLAUDE_PLUGIN_ROOT` liveness | Substitution in skill, agent, hook, MCP, LSP, monitor, and `allowed-tools` content is the documented contract ([plugins reference](https://code.claude.com/docs/en/plugins-reference#environment-variables); ADR 0007, updated 2026-08-04). Unset as a Bash-tool environment variable is a different surface from skill-body substitution; ADR 0007's version-stamped record is the evidence for which surface expands the variable, so `${CLAUDE_PLUGIN_ROOT}/scripts/...` lines in skill markdown are not made inert by it. Call sites in `worktree` `context/status.md` and `context/audit.md` stay as written. No fleet rewrite. | **adopt** (record the distinction; no call-site change) |
| 2. Toolchain pin vs measured CLI | Original gap was pin **2.1.238** against measured 2.1.240 / 2.1.241 (#3113). Origin/main now pins **2.1.283**. Policy: the CI pin tracks the toolchain this repo's gates and empirical work run against; do not leave it lagging a version-stamped claim. No lag-policy doc beyond this row. | **adopt** (gap dissolved; pin-tracks-work) |
| 3. Windows worktree test failures | Last measured 2026-08-23 on a Windows host: `worktree-root-doctor.test.sh` 9 failures, `worktree-add-containment-gate.test.sh` 2 failures, confirmed against pristine base. Those suites still have no host-skip. #3683 host-skipped other Git Bash path-form suites, not these two. Fix direction (Windows support vs an explicit platform guard) needs a Windows host and a product call. | **defer** (capability-gated; file a child when an operator has a Windows host) |
| 4. `check-drive-root-litter.sh` machine-state sensitivity | The script is a host-wide advisory scan of drive roots, not a repo-scoped gate. That is already the design: header "ADVISORY BY DEFAULT"; [windows-path-emit](conventions/windows-path-emit/README.md) "The detection net". [ADR 0003](adr/0003-verification-guards-earn-default-on-by-measured-precision.md) supplies the principle only. Non-Windows is a reported no-op. Operators with a deliberate `C:\tmp` set `DRIVE_ROOT_LITTER_IGNORE_SINKS=tmp`. Do not scope it to the repo; the defect it detects is host litter. | **adopt** (reaffirm host-wide advisory) |

## What this close is not

- Not a fleet sweep of interpolating call sites.
- Not a `package.json` bump (already current).
- Not Windows support or a platform guard for the two worktree suites.
- Not promoting `check-drive-root-litter.sh` into a required live lane.
