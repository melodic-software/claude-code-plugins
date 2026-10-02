# The built-in `/recap` command: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row is a four-part
record: the claim, the basis it rests on, the date it was checked, and the event that makes it
worth checking again.

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `recap` is a built-in command described as "Generate a one-line session recap now", with no argument hint and no alias | The `/harness-ops:inventory` extraction of the installed 2.1.284 binary (`builtin_commands.recap`) | 2026-09-29 | A release renames or removes `recap`, or changes its description |
| It is user-invocable and not model-invocable, and it is not gated behind a setting | Same extraction: `user_invocable: true`, `model_invocable: false`, `gated: false` | 2026-09-29 | A release changes its invocability or adds a gate |
| The commands page describes it as "Generate a one-line summary of the current session on demand" and points to the automatic session recap shown after you have been away | The `/recap` row on <https://code.claude.com/docs/en/commands> | 2026-09-29 | The commands page row changes or disappears |
| The recap feature and manual `/recap` arrived together, configurable in `/config` | Claude Code changelog, 2.1.108 ("Added recap feature ... manually invocable with `/recap`") | 2026-09-29 | A release note changes what `/recap` summarizes |
| `/recap` declines with a short notice when relayed from a chat thread, a routine, or a webhook; typed in the terminal, the apps, Remote Control, `-p`, or an SDK host, it runs | Claude Code changelog, 2.1.284 | 2026-09-29 | A release note changes where `/recap` runs |
| Recap text is capped at 400 characters | Claude Code changelog, 2.1.236 ("recap text (automatic and `/recap`) is now capped at 400 characters") | 2026-09-29 | A release note changes the cap |

## Why the verdict is complementary

`/recap` summarizes the conversation in one line and reads nothing else. This skill reads the
durable state on disk and the work running off this thread, which the recap never sees, and
produces a four-part briefing. Neither replaces the other: a person who only needs the one-line
reminder is better served by `/recap`, so this skill offers it rather than imitating it.
