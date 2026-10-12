# The built-in `/recap` command: verification record

Detail behind the `## Boundary` section in [SKILL.md](../SKILL.md). Each row holds our decision,
the pointer to read live, the date it was checked, and the event that makes it worth checking
again.

| Decision | Pointer | As of | Recheck when |
|---|---|---|---|
| Treat `recap` as an ungated, user-invocable built-in the model cannot invoke, so this skill offers it and never runs it | Probe: the `/harness-ops:inventory` extraction of the installed 2.1.284 binary (`builtin_commands.recap`), observed 2026-09-29 | 2026-10-11 | A release renames or removes `recap`, or changes its invocability or adds a gate |
| Offer `/recap` for a one-line reminder of the conversation; read what it summarizes and the automatic recap it pairs with live | The `/recap` row of [Commands § All commands](https://code.claude.com/docs/en/commands#all-commands) and [Interactive mode § Session recap](https://code.claude.com/docs/en/interactive-mode#session-recap) | 2026-10-11 | Either changes what the recap summarizes, or the row disappears |
| Read where `/recap` runs and any limit on its length from the release notes, not from memory | [Changelog § 2.1.108](https://code.claude.com/docs/en/changelog#2-1-108), [§ 2.1.236](https://code.claude.com/docs/en/changelog#2-1-236), and [§ 2.1.284](https://code.claude.com/docs/en/changelog#2-1-284) | 2026-10-11 | A release note changes where `/recap` runs or how long its text can be |

## Why the verdict is complementary

`/recap` summarizes the conversation in one line and reads nothing else. This skill reads the
durable state on disk and the work running off this thread, which the recap never sees, and
produces a four-part briefing. Neither replaces the other: a person who only needs the one-line
reminder is better served by `/recap`, so this skill offers it rather than imitating it.
