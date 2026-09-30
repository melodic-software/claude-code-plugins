# The built-in `/auto-mode-setup` command, as this skill relates to it

Four-part records behind the `## Boundary` section in `SKILL.md`. The section carries the
conclusion; this file carries what it rests on. Nothing here asserts that the command is present in
any session.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `/auto-mode-setup` is a built-in command, user-invocable only, hidden from the command menu, and gated; its description is "Teach auto mode about your environment, plus optional rule tweaks" | The `/claude-ops:inventory` extraction of the installed 2.1.284 binary (`model_invocable: false`, `user_invocable: true`, `hidden: true`, `gated: true`) | 2026-09-29, Claude Code 2.1.284 | A release renames or removes the command, or changes its invocability or hidden flag |
| It drafts `autoMode.environment` entries from the project and recent sessions, then lets the person review the draft and save it to user settings | Commands reference row for `/auto-mode-setup`, <https://code.claude.com/docs/en/commands> | 2026-09-29 | The commands page row changes |
| It requires a Pro, Max, or Team plan and Claude Code v2.1.228 or later, v2.1.233 or later on native Windows | Same commands reference row | 2026-09-29 | The commands page row changes its plan or version requirements |
| Its argument hint is `[--request-id <uuid>] (--wizard posture=... scope=... depth=... --propose \| --expect-sha256 <64-hex> --apply-file <path>)`: a propose step and a hash-checked apply step | The `/claude-ops:inventory` extraction of the installed 2.1.284 binary | 2026-09-29, Claude Code 2.1.284 | A release changes the argument hint |

## Why the verdict is complementary

The command writes: it produces `environment` entries and saves them to user settings after the
person reviews them. The commands page documents it for `environment` entries only; its "optional
rule tweaks" are not described there. This skill never writes and covers every classifier section,
with an interview for stated exclusions and a condition the classifier can see in the transcript.
Using the command for `environment` and this skill for the rest composes cleanly, since the
command's save is what Phase 1 then reads.
