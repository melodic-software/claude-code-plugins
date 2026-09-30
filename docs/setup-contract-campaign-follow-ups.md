# Setup-contract campaign follow-ups (#3138)

The four follow-ups from the #3111 / #3112 / #3113 / #3127 campaign, bundled in
[#3138](https://github.com/melodic-software/claude-code-plugins/issues/3138), and how each is
settled.

**Claim:** `${CLAUDE_PLUGIN_ROOT}` expands in a skill body but stays literal in a `context/` file
read via `Read`, and the Bash tool's environment does not carry it. The `worktree` skill therefore
resolves the scripts directory in `SKILL.md` and its `context/` files use `<scripts-dir>`. The
Claude Code pin follows the Dependabot policy in `.github/dependabot.yml`. The two worktree suites
skip on Windows Git Bash hosts. `scripts/check-drive-root-litter.sh` stays a host-wide advisory
scan.

**Basis:** the `worktree` `SKILL.md` "Scripts directory (resolved)" line holds the measured probe
(two headless `claude -p` runs on Claude Code 2.1.284); `.github/dependabot.yml` lines 49-51 (the
daily schedule for the executable compatibility dependency) and 53-59 (the cooldown, with
`@anthropic-ai/claude-code` excluded); the host gate at the top of
`plugins/source-control/scripts/worktree-root-doctor.test.sh` and
`plugins/source-control/hooks/worktree-add-containment-gate.test.sh`, which cite
[#5350](https://github.com/melodic-software/claude-code-plugins/issues/5350); the
"ADVISORY BY DEFAULT" header of `scripts/check-drive-root-litter.sh`.

**As of:** 2026-09-29, Claude Code 2.1.284.

**Recheck:** a Claude Code release note that changes plugin-variable substitution or the Bash tool
environment; a change to the Dependabot Claude Code entry; #5350 landing Windows support for the
two suites; a maintainer wiring `check-drive-root-litter.sh` into a required live lane.

## Positions

| Follow-up | Position |
| --- | --- |
| 1. `CLAUDE_PLUGIN_ROOT` liveness | Fixed at the call sites. A `context/` file is read as raw bytes, so the token reaches Bash literal and the command exits 127. `worktree/SKILL.md` carries the resolved scripts directory, and `context/status.md`, `audit.md`, `cleanup.md` and `create.md` call helpers through `<scripts-dir>`, to be substituted before a command reaches Bash. |
| 2. Toolchain pin vs measured CLI | `.github/dependabot.yml` lines 49-51 keep the pin on a daily schedule, and lines 53-59 exclude `@anthropic-ai/claude-code` from the cooldown so bumps arrive immediately. No separate lag policy. |
| 3. Windows worktree test failures | Both suites host-skip on Windows Git Bash with a visible SKIP line naming [#5350](https://github.com/melodic-software/claude-code-plugins/issues/5350). Real Windows support is that issue's work and needs a Windows host. |
| 4. `check-drive-root-litter.sh` machine-state sensitivity | A host-wide advisory scan of drive roots, not a repo-scoped gate: the script header says "ADVISORY BY DEFAULT" and [windows-path-emit](conventions/windows-path-emit/README.md) "The detection net" describes the host fingerprint it detects. Non-Windows is a reported no-op. An operator with a deliberate `C:\tmp` sets `DRIVE_ROOT_LITTER_IGNORE_SINKS=tmp`. |

## What this close is not

- Not a fleet sweep of interpolating call sites beyond the `worktree` `context/` files.
- Not a `package.json` bump or a change to the Dependabot policy.
- Not Windows support for the two worktree suites; #5350 owns that.
- Not promoting `check-drive-root-litter.sh` into a required live lane.
